/**
 * @description Runs Summary report(s) and returns commission-oriented results: per-rep values, measure metadata, errors.
 *              Use getCommissionReportData for one report; getCommissionDataForReportIds for distinct Ids (one run each).
 *              See docs/INTEGRATION_GUIDE.md.
 */
public with sharing class CommissionResultsController {

    private static final String REPORT_TYPE_SUMMARY = 'SUMMARY';
    private static final String REPORT_TYPE_TABULAR = 'TABULAR';
    private static final String REPORT_TYPE_MATRIX = 'MATRIX';
    private static final String REPORT_TYPE_JOINED = 'JOINED';

    private static final String BLANK_KEY_TOKEN = '(Blank)';
    private static final String KEY_SEPARATOR = '||';

    public static final String VISIBILITY_ALL = 'ALL';
    public static final String VISIBILITY_MY_RECORDS = 'MY_RECORDS';
    public static final String VISIBILITY_MY_TEAM = 'MY_TEAM';
    public static final Integer MAX_ROWS_CAP = 2000;
    public static final Integer DEFAULT_MAX_ROWS = 2000;

    public static final String COL_USER_ID = 'commission_UserId';
    public static final String COL_USER_NAME = 'commission_UserName';
    public static final String COL_CONTEXT = 'commission_Context';

    /**
     * Test seam: when non-null and contains reportId, skip runReport and use that parsed snapshot.
     */
    @TestVisible
    private static Map<Id, CommissionParsedReport> testParsedReportById = null;

    /**
     * @param reportId Summary report Id (1-2 row groupings; user rep should be primary or inner grouping).
     * @param maxRows Max data rows (excluding grand total); null uses DEFAULT_MAX_ROWS; capped at MAX_ROWS_CAP.
     * @param dataVisibility ALL | MY_RECORDS | MY_TEAM (classic report scope).
     * @param showGrandTotalRow When true, include grand total row from report.
     */
    @AuraEnabled(cacheable = true)
    public static CommissionReportResult getCommissionReportData(
        Id reportId,
        Integer maxRows,
        String dataVisibility,
        Boolean showGrandTotalRow
    ) {
        Long t0 = System.currentTimeMillis();
        CommissionReportResult result = new CommissionReportResult();

        Integer effectiveMax = maxRows == null ? DEFAULT_MAX_ROWS : maxRows;
        if (effectiveMax < 1) {
            effectiveMax = DEFAULT_MAX_ROWS;
        }
        if (effectiveMax > MAX_ROWS_CAP) {
            effectiveMax = MAX_ROWS_CAP;
        }

        String visibility = String.isBlank(dataVisibility) ? VISIBILITY_ALL : dataVisibility.toUpperCase();
        Boolean grandTotal = showGrandTotalRow == null ? true : showGrandTotalRow;

        if (reportId == null) {
            result.errors.add(new CommissionReportResult.ReportError(null, 'Report Id is required', true));
            result.processingTimeMs = System.currentTimeMillis() - t0;
            return result;
        }

        try {
            CommissionParsedReport parsed;
            if (Test.isRunningTest() && testParsedReportById != null && testParsedReportById.containsKey(reportId)) {
                parsed = testParsedReportById.get(reportId);
            } else {
                parsed = fetchAndParseReport(reportId, visibility);
            }

            if (String.isNotBlank(parsed.reportName)) {
                result.reportNames.put(String.valueOf(reportId), parsed.reportName);
            }

            if (!parsed.isValid) {
                result.errors.add(
                    new CommissionReportResult.ReportError(String.valueOf(reportId), parsed.errorMessage, true)
                );
                result.errors[0].reportName = parsed.reportName;
                result.processingTimeMs = System.currentTimeMillis() - t0;
                return result;
            }

            buildResultFromParsed(parsed, result, effectiveMax, grandTotal);
        } catch (Exception e) {
            System.debug(
                LoggingLevel.ERROR,
                'CommissionResultsController: ' + e.getMessage() + '\n' + e.getStackTraceString()
            );
            result.errors.add(
                new CommissionReportResult.ReportError(null, formatErrorMessage(e), true)
            );
        }

        result.processingTimeMs = System.currentTimeMillis() - t0;
        return result;
    }

    /**
     * @description Convenience overload with defaults (max rows, ALL visibility, grand total on).
     */
    public static CommissionReportResult getCommissionReportData(Id reportId) {
        return getCommissionReportData(reportId, null, null, null);
    }

    /**
     * @description One getCommissionReportData call per distinct non-null report Id (use when mapping metadata references multiple reports).
     */
    public static Map<Id, CommissionReportResult> getCommissionDataForReportIds(
        Set<Id> reportIds,
        Integer maxRows,
        String dataVisibility,
        Boolean showGrandTotalRow
    ) {
        Map<Id, CommissionReportResult> out = new Map<Id, CommissionReportResult>();
        if (reportIds == null || reportIds.isEmpty()) {
            return out;
        }
        for (Id reportId : reportIds) {
            if (reportId == null) {
                continue;
            }
            out.put(
                reportId,
                getCommissionReportData(reportId, maxRows, dataVisibility, showGrandTotalRow)
            );
        }
        return out;
    }

    public static Map<Id, CommissionReportResult> getCommissionDataForReportIds(Set<Id> reportIds) {
        return getCommissionDataForReportIds(reportIds, null, null, null);
    }

    public static Map<Id, CommissionReportResult> getCommissionDataForReportIds(
        List<Id> reportIds,
        Integer maxRows,
        String dataVisibility,
        Boolean showGrandTotalRow
    ) {
        if (reportIds == null || reportIds.isEmpty()) {
            return new Map<Id, CommissionReportResult>();
        }
        return getCommissionDataForReportIds(new Set<Id>(reportIds), maxRows, dataVisibility, showGrandTotalRow);
    }

    public static Map<Id, CommissionReportResult> getCommissionDataForReportIds(List<Id> reportIds) {
        return getCommissionDataForReportIds(reportIds, null, null, null);
    }

    /**
     * @description Runs each distinct report referenced in mappingAttributes once, then fills per-rep maps:
     *              targetFieldApiName → numeric value from the report (null if missing).
     *              repIds null/empty → every distinct userId seen across those reports (sorted). Otherwise only listed reps (deduped).
     */
    @AuraEnabled
    public static CommissionIngestionResult buildCommissionValuesForReps(
        List<Id> repIds,
        List<CommissionMappingAttribute> mappingAttributes,
        Integer maxRows,
        String dataVisibility,
        Boolean showGrandTotalRow
    ) {
        CommissionIngestionResult out = new CommissionIngestionResult();
        if (mappingAttributes == null || mappingAttributes.isEmpty()) {
            out.errors.add('mappingAttributes is required');
            return out;
        }

        Set<Id> reportIds = new Set<Id>();
        for (CommissionMappingAttribute ma : mappingAttributes) {
            if (ma != null && ma.sourceReportId != null) {
                reportIds.add(ma.sourceReportId);
            }
        }
        if (reportIds.isEmpty()) {
            out.errors.add('No sourceReportId values in mapping attributes');
            return out;
        }

        Map<Id, CommissionReportResult> byReport = getCommissionDataForReportIds(
            reportIds,
            maxRows,
            dataVisibility,
            showGrandTotalRow
        );

        return buildCommissionValuesFromReportResults(repIds, mappingAttributes, byReport);
    }

    /**
     * @description Label-based mapping variant. Resolve source measure by report label (and optional aggregate type),
     *              then return targetFieldApiName -> Decimal value for each requested user.
     */
    @AuraEnabled
    public static CommissionIngestionResult buildCommissionValuesForRepsByLabel(
        List<Id> repIds,
        List<CommissionFieldMappingRequest> fieldMappings,
        Integer maxRows,
        String dataVisibility,
        Boolean showGrandTotalRow
    ) {
        CommissionIngestionResult out = new CommissionIngestionResult();
        if (fieldMappings == null || fieldMappings.isEmpty()) {
            out.errors.add('fieldMappings is required');
            return out;
        }

        Set<Id> reportIds = new Set<Id>();
        for (CommissionFieldMappingRequest fm : fieldMappings) {
            if (fm != null && fm.sourceReportId != null) {
                reportIds.add(fm.sourceReportId);
            }
        }
        if (reportIds.isEmpty()) {
            out.errors.add('No sourceReportId values in fieldMappings');
            return out;
        }

        Map<Id, CommissionReportResult> byReport = getCommissionDataForReportIds(
            reportIds,
            maxRows,
            dataVisibility,
            showGrandTotalRow
        );

        List<CommissionMappingAttribute> resolvedMappings = new List<CommissionMappingAttribute>();
        for (CommissionFieldMappingRequest fm : fieldMappings) {
            if (fm == null) {
                continue;
            }
            CommissionMappingAttribute ma = new CommissionMappingAttribute();
            ma.targetFieldApiName = fm.targetFieldApiName;
            ma.sourceReportId = fm.sourceReportId;

            if (String.isBlank(fm.targetFieldApiName)) {
                out.warnings.add('Skipped mapping with blank targetFieldApiName.');
                continue;
            }
            if (fm.sourceReportId == null) {
                out.errors.add('Mapping for ' + fm.targetFieldApiName + ' is missing sourceReportId.');
                resolvedMappings.add(ma);
                continue;
            }
            if (String.isBlank(fm.sourceFieldLabel)) {
                out.errors.add('Mapping for ' + fm.targetFieldApiName + ' is missing sourceFieldLabel.');
                resolvedMappings.add(ma);
                continue;
            }

            CommissionReportResult reportResult = byReport.get(fm.sourceReportId);
            if (reportResult == null) {
                out.errors.add(
                    'Report ' + String.valueOf(fm.sourceReportId) + ' was not loaded for mapping ' + fm.targetFieldApiName + '.'
                );
                resolvedMappings.add(ma);
                continue;
            }

            List<CommissionReportResult.MeasureColumn> candidates = new List<CommissionReportResult.MeasureColumn>();
            String wantedLabel = normalizeLabelForMatch(fm.sourceFieldLabel);
            for (CommissionReportResult.MeasureColumn mc : reportResult.measures) {
                if (String.isBlank(mc.aggregateKey)) {
                    continue;
                }
                if (normalizeLabelForMatch(mc.label) == wantedLabel) {
                    candidates.add(mc);
                }
            }

            if (!String.isBlank(fm.preferredAggregateType) && !candidates.isEmpty()) {
                String wantedAggType = normalizeAggregateType(fm.preferredAggregateType);
                List<CommissionReportResult.MeasureColumn> filtered = new List<CommissionReportResult.MeasureColumn>();
                for (CommissionReportResult.MeasureColumn c : candidates) {
                    if (normalizeAggregateType(inferAggregateType(c)) == wantedAggType) {
                        filtered.add(c);
                    }
                }
                candidates = filtered;
            }

            if (candidates.isEmpty()) {
                out.errors.add(
                    'Mapping ' +
                    fm.targetFieldApiName +
                    ' could not resolve sourceFieldLabel "' +
                    fm.sourceFieldLabel +
                    '" on report ' +
                    String.valueOf(fm.sourceReportId) +
                    '.'
                );
            } else if (candidates.size() > 1) {
                out.errors.add(
                    'Mapping ' +
                    fm.targetFieldApiName +
                    ' is ambiguous for sourceFieldLabel "' +
                    fm.sourceFieldLabel +
                    '" on report ' +
                    String.valueOf(fm.sourceReportId) +
                    '. Provide preferredAggregateType.'
                );
            } else {
                ma.sourceAggregateKey = candidates[0].aggregateKey;
            }

            resolvedMappings.add(ma);
        }

        CommissionIngestionResult computed = buildCommissionValuesFromReportResults(
            repIds,
            resolvedMappings,
            byReport
        );
        out.repRows = computed.repRows;
        out.warnings.addAll(computed.warnings);
        out.errors.addAll(computed.errors);
        return out;
    }

    public static CommissionIngestionResult buildCommissionValuesForRepsByLabel(
        List<Id> repIds,
        List<CommissionFieldMappingRequest> fieldMappings
    ) {
        return buildCommissionValuesForRepsByLabel(repIds, fieldMappings, null, null, null);
    }

    private static CommissionIngestionResult buildCommissionValuesFromReportResults(
        List<Id> repIds,
        List<CommissionMappingAttribute> mappingAttributes,
        Map<Id, CommissionReportResult> byReport
    ) {
        CommissionIngestionResult out = new CommissionIngestionResult();

        Map<Id, Map<String, String>> aggKeyToValueKeyByReport = new Map<Id, Map<String, String>>();
        Map<Id, Map<String, CommissionReportResult.RepData>> repDataByReport = new Map<Id, Map<String, CommissionReportResult.RepData>>();
        Set<String> allUserIds = new Set<String>();

        for (Id rptId : byReport.keySet()) {
            CommissionReportResult cr = byReport.get(rptId);
            out.warnings.addAll(cr.warnings);
            for (CommissionReportResult.ReportError err : cr.errors) {
                if (err.isFatal) {
                    out.errors.add(
                        'Report ' + String.valueOf(rptId) + (String.isNotBlank(err.reportName) ? ' (' + err.reportName + ')' : '') + ': ' +
                        err.message
                    );
                }
            }

            Map<String, String> aggToCol = new Map<String, String>();
            for (CommissionReportResult.MeasureColumn mc : cr.measures) {
                if (String.isNotBlank(mc.aggregateKey) && String.isNotBlank(mc.key)) {
                    aggToCol.put(mc.aggregateKey, mc.key);
                }
            }
            aggKeyToValueKeyByReport.put(rptId, aggToCol);

            Map<String, CommissionReportResult.RepData> byUser = new Map<String, CommissionReportResult.RepData>();
            Boolean warned2dDup = false;
            for (CommissionReportResult.RepData rep : cr.reps) {
                if (rep.isTotalRow == true || String.isBlank(rep.userId)) {
                    continue;
                }
                if (byUser.containsKey(rep.userId) && cr.hasContextDimension == true && !warned2dDup) {
                    out.warnings.add(
                        'Report ' +
                        String.valueOf(rptId) +
                        ': multiple rows for the same user Id (two row groupings); last row wins for buildCommissionValuesForReps.'
                    );
                    warned2dDup = true;
                }
                byUser.put(rep.userId, rep);
                allUserIds.add(rep.userId);
            }
            repDataByReport.put(rptId, byUser);
        }

        List<String> repOrder = new List<String>();
        if (repIds != null && !repIds.isEmpty()) {
            Set<String> seen = new Set<String>();
            for (Id uid : repIds) {
                if (uid == null) {
                    continue;
                }
                String key = String.valueOf(uid);
                if (seen.add(key)) {
                    repOrder.add(key);
                }
            }
        } else {
            repOrder.addAll(allUserIds);
            repOrder.sort();
        }

        for (String uid : repOrder) {
            CommissionIngestionResult.RepIngestionRow row = new CommissionIngestionResult.RepIngestionRow();
            row.userId = uid;

            for (CommissionMappingAttribute ma : mappingAttributes) {
                if (ma == null || String.isBlank(ma.targetFieldApiName)) {
                    continue;
                }
                if (ma.sourceReportId == null || String.isBlank(ma.sourceAggregateKey)) {
                    row.fieldValues.put(ma.targetFieldApiName, null);
                    continue;
                }

                Map<String, CommissionReportResult.RepData> byUser = repDataByReport.get(ma.sourceReportId);
                Map<String, String> aggToCol = aggKeyToValueKeyByReport.get(ma.sourceReportId);
                if (byUser == null || aggToCol == null) {
                    row.fieldValues.put(ma.targetFieldApiName, null);
                    continue;
                }

                String valueKey = aggToCol.get(ma.sourceAggregateKey);
                CommissionReportResult.RepData rd = byUser.get(uid);
                if (valueKey == null || rd == null) {
                    row.fieldValues.put(ma.targetFieldApiName, null);
                } else {
                    row.fieldValues.put(ma.targetFieldApiName, rd.values.get(valueKey));
                }
            }
            out.repRows.add(row);
        }

        return out;
    }

    public static CommissionIngestionResult buildCommissionValuesForReps(
        List<Id> repIds,
        List<CommissionMappingAttribute> mappingAttributes
    ) {
        return buildCommissionValuesForReps(repIds, mappingAttributes, null, null, null);
    }

    private static String normalizeLabelForMatch(String label) {
        return String.isBlank(label) ? '' : label.trim().toLowerCase();
    }

    private static String normalizeAggregateType(String aggregateType) {
        return String.isBlank(aggregateType) ? '' : aggregateType.trim().toUpperCase();
    }

    private static String inferAggregateType(CommissionReportResult.MeasureColumn mc) {
        if (mc == null) {
            return '';
        }
        if (mc.aggregateKey == 'RowCount') {
            return 'COUNT';
        }
        String label = mc.label == null ? '' : mc.label.toLowerCase();
        if (label.startsWith('sum of ')) {
            return 'SUM';
        }
        if (label.startsWith('average of ')) {
            return 'AVG';
        }
        if (label.startsWith('max of ')) {
            return 'MAX';
        }
        if (label.startsWith('min of ')) {
            return 'MIN';
        }
        return '';
    }

    private static CommissionParsedReport fetchAndParseReport(Id reportId, String dataVisibility) {
        CommissionParsedReport parsed = new CommissionParsedReport();
        parsed.reportId = String.valueOf(reportId);

        try {
            Reports.ReportDescribeResult describe = Reports.ReportManager.describeReport(reportId);
            Reports.ReportMetadata metadata = describe.getReportMetadata();
            parsed.reportName = metadata.getName();

            String reportFormat = metadata.getReportFormat().name();
            if (reportFormat == REPORT_TYPE_JOINED) {
                parsed.isValid = false;
                parsed.errorMessage = 'Joined reports are not supported: ' + parsed.reportName;
                return parsed;
            }
            if (reportFormat == REPORT_TYPE_MATRIX) {
                parsed.isValid = false;
                parsed.errorMessage = 'Matrix reports are not supported: ' + parsed.reportName;
                return parsed;
            }
            if (reportFormat == REPORT_TYPE_TABULAR) {
                parsed.isValid = false;
                parsed.errorMessage = 'Tabular reports are not supported: ' + parsed.reportName;
                return parsed;
            }

            List<Reports.GroupingInfo> groupingsDown = metadata.getGroupingsDown();
            if (groupingsDown == null || groupingsDown.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'Report must have at least one row grouping: ' + parsed.reportName;
                return parsed;
            }

            List<Reports.GroupingInfo> groupingsAcross = metadata.getGroupingsAcross();
            if (groupingsAcross != null && !groupingsAcross.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'Column groupings are not supported: ' + parsed.reportName;
                return parsed;
            }

            parsed.dimensionCount = groupingsDown.size();
            parsed.groupingField = groupingsDown[0].getName();
            if (parsed.dimensionCount >= 2) {
                parsed.secondGroupingField = groupingsDown[1].getName();
            }
            if (parsed.dimensionCount > 2) {
                parsed.isValid = false;
                parsed.errorMessage = 'Maximum 2 row groupings supported: ' + parsed.reportName;
                return parsed;
            }

            // Inner grouping = commission rep / user lookup (common pattern: Status × Origin Rep).
            parsed.userGroupingOrdinal = parsed.dimensionCount == 2 ? 1 : 0;
            parsed.userGroupingFieldName = parsed.dimensionCount == 2
                ? parsed.secondGroupingField
                : parsed.groupingField;

            if (shouldOverrideScope(dataVisibility)) {
                String scope = toReportScope(dataVisibility);
                if (scope != null) {
                    metadata.setScope(scope);
                }
            }

            Reports.ReportResults results;
            if (shouldOverrideScope(dataVisibility)) {
                results = Reports.ReportManager.runReport(reportId, metadata, true);
            } else {
                results = Reports.ReportManager.runReport(reportId, true);
            }

            Map<String, Reports.AggregateColumn> aggColumns = results.getReportExtendedMetadata()
                .getAggregateColumnInfo();
            if (aggColumns == null || aggColumns.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'Report has no aggregates: ' + parsed.reportName;
                return parsed;
            }

            List<String> orderedAggKeys = metadata.getAggregates();
            if (orderedAggKeys == null || orderedAggKeys.isEmpty()) {
                orderedAggKeys = new List<String>(aggColumns.keySet());
            }

            for (Integer i = 0; i < orderedAggKeys.size(); i++) {
                String aggKey = orderedAggKeys[i];
                Reports.AggregateColumn agg = aggColumns.get(aggKey);
                if (agg == null) {
                    continue;
                }
                Reports.ColumnDataType dataType = agg.getDataType();
                if (dataType == Reports.ColumnDataType.CURRENCY_DATA ||
                    dataType == Reports.ColumnDataType.INT_DATA ||
                    dataType == Reports.ColumnDataType.DOUBLE_DATA ||
                    dataType == Reports.ColumnDataType.PERCENT_DATA ||
                    aggKey == 'RowCount') {
                    parsed.aggregates.add(
                        new CommissionReportResult.AggregateInfo(
                            aggKey,
                            agg.getLabel(),
                            String.valueOf(dataType),
                            i
                        )
                    );
                }
            }

            if (parsed.aggregates.isEmpty()) {
                parsed.isValid = false;
                parsed.errorMessage = 'No numeric aggregates found: ' + parsed.reportName;
                return parsed;
            }

            if (parsed.dimensionCount == 1) {
                extractSingleDimensionData(results, parsed);
            } else {
                extractTwoDimensionData(results, parsed);
            }
        } catch (System.NoAccessException e) {
            parsed.isValid = false;
            parsed.errorMessage = 'You don\'t have access to this report';
        } catch (Exception e) {
            parsed.isValid = false;
            String msg = e.getMessage();
            if (msg != null && msg.contains('insufficient access')) {
                parsed.errorMessage = 'You don\'t have access to run this report: ' + parsed.reportName;
            } else {
                parsed.errorMessage = 'Error processing report: ' + msg;
            }
        }

        return parsed;
    }

    private static Boolean shouldOverrideScope(String dataVisibility) {
        return dataVisibility != null &&
            dataVisibility != VISIBILITY_ALL &&
            (dataVisibility == VISIBILITY_MY_RECORDS || dataVisibility == VISIBILITY_MY_TEAM);
    }

    private static String toReportScope(String dataVisibility) {
        if (dataVisibility == VISIBILITY_MY_RECORDS) {
            return 'user';
        }
        if (dataVisibility == VISIBILITY_MY_TEAM) {
            return 'team';
        }
        return null;
    }

    private static void extractSingleDimensionData(
        Reports.ReportResults results,
        CommissionParsedReport parsed
    ) {
        Map<String, Reports.ReportFact> factMap = results.getFactMap();
        Reports.Dimension downDimension = results.getGroupingsDown();
        List<Reports.GroupingValue> groupings = downDimension.getGroupings();

        for (Reports.GroupingValue grouping : groupings) {
            String primaryKey = normalizeKey(grouping.getValue());
            String primaryLabel = grouping.getLabel();
            String factKey = grouping.getKey() + '!T';
            String compositeKey = primaryKey;
            parsed.labelsByKey.put(compositeKey, primaryLabel);
            if (!parsed.valuesByKeyByAggregate.containsKey(compositeKey)) {
                parsed.valuesByKeyByAggregate.put(compositeKey, new Map<String, Decimal>());
            }
            fillFactAggregates(factMap, factKey, parsed, compositeKey);
        }
        fillGrandTotals(factMap, parsed);
    }

    private static void extractTwoDimensionData(
        Reports.ReportResults results,
        CommissionParsedReport parsed
    ) {
        Map<String, Reports.ReportFact> factMap = results.getFactMap();
        Reports.Dimension downDimension = results.getGroupingsDown();
        List<Reports.GroupingValue> topGroupings = downDimension.getGroupings();

        for (Reports.GroupingValue topGrouping : topGroupings) {
            String primaryKey = normalizeKey(topGrouping.getValue());
            String primaryLabel = topGrouping.getLabel();
            List<Reports.GroupingValue> childGroupings = topGrouping.getGroupings();
            if (childGroupings == null) {
                continue;
            }
            for (Reports.GroupingValue childGrouping : childGroupings) {
                String secondaryKey = normalizeKey(childGrouping.getValue());
                String secondaryLabel = childGrouping.getLabel();
                String factKey = childGrouping.getKey() + '!T';
                String compositeKey = primaryKey + KEY_SEPARATOR + secondaryKey;
                parsed.labelsByKey.put(compositeKey, primaryLabel);
                parsed.secondLabelsByKey.put(compositeKey, secondaryLabel);
                if (!parsed.valuesByKeyByAggregate.containsKey(compositeKey)) {
                    parsed.valuesByKeyByAggregate.put(compositeKey, new Map<String, Decimal>());
                }
                fillFactAggregates(factMap, factKey, parsed, compositeKey);
            }
        }
        fillGrandTotals(factMap, parsed);
    }

    private static void fillFactAggregates(
        Map<String, Reports.ReportFact> factMap,
        String factKey,
        CommissionParsedReport parsed,
        String compositeKey
    ) {
        if (!factMap.containsKey(factKey)) {
            return;
        }
        Reports.ReportFact fact = factMap.get(factKey);
        List<Reports.SummaryValue> summaryValues = fact.getAggregates();
        for (CommissionReportResult.AggregateInfo aggInfo : parsed.aggregates) {
            Decimal value = null;
            if (summaryValues != null && aggInfo.index < summaryValues.size()) {
                value = convertToDecimal(summaryValues[aggInfo.index].getValue());
            }
            parsed.valuesByKeyByAggregate.get(compositeKey).put(aggInfo.key, value);
        }
    }

    private static void fillGrandTotals(
        Map<String, Reports.ReportFact> factMap,
        CommissionParsedReport parsed
    ) {
        if (!factMap.containsKey('T!T')) {
            return;
        }
        Reports.ReportFact totalFact = factMap.get('T!T');
        List<Reports.SummaryValue> totalValues = totalFact.getAggregates();
        for (CommissionReportResult.AggregateInfo aggInfo : parsed.aggregates) {
            Decimal total = null;
            if (totalValues != null && aggInfo.index < totalValues.size()) {
                total = convertToDecimal(totalValues[aggInfo.index].getValue());
            }
            parsed.grandTotals.put(aggInfo.key, total);
        }
    }

    private static void buildResultFromParsed(
        CommissionParsedReport parsed,
        CommissionReportResult result,
        Integer maxRows,
        Boolean showGrandTotalRow
    ) {
        result.hasContextDimension = parsed.dimensionCount == 2;
        result.contextGroupingFieldName = parsed.dimensionCount == 2 ? parsed.groupingField : null;
        result.userGroupingFieldApiName = parsed.userGroupingFieldName;

        CommissionReportResult.MeasureColumn cUid = new CommissionReportResult.MeasureColumn();
        cUid.key = COL_USER_ID;
        cUid.label = 'User Id';
        cUid.dataType = 'STRING_DATA';
        cUid.isKeyColumn = true;
        cUid.reportId = parsed.reportId;
        result.measures.add(cUid);

        CommissionReportResult.MeasureColumn cName = new CommissionReportResult.MeasureColumn();
        cName.key = COL_USER_NAME;
        cName.label = 'Name';
        cName.dataType = 'STRING_DATA';
        cName.reportId = parsed.reportId;
        result.measures.add(cName);

        if (parsed.dimensionCount == 2) {
            CommissionReportResult.MeasureColumn cCtx = new CommissionReportResult.MeasureColumn();
            cCtx.key = COL_CONTEXT;
            cCtx.label = humanizeFieldName(parsed.groupingField);
            cCtx.dataType = 'STRING_DATA';
            cCtx.reportId = parsed.reportId;
            result.measures.add(cCtx);
        }

        for (CommissionReportResult.AggregateInfo agg : parsed.aggregates) {
            CommissionReportResult.MeasureColumn c = new CommissionReportResult.MeasureColumn();
            c.key = 'agg_' + sanitizeKey(agg.key);
            c.label = agg.label;
            c.dataType = agg.dataType;
            c.aggregateKey = agg.key;
            c.reportId = parsed.reportId;
            c.currencyCode = UserInfo.getDefaultCurrency();
            result.measures.add(c);
        }

        List<String> keys = new List<String>(parsed.valuesByKeyByAggregate.keySet());
        keys.sort();

        result.totalRowCount = keys.size();
        Integer rowBudget = maxRows;
        for (String compositeKey : keys) {
            if (rowBudget <= 0) {
                result.isTruncated = true;
                break;
            }
            CommissionReportResult.RepData row = buildRow(parsed, compositeKey);
            result.reps.add(row);
            rowBudget--;
        }

        if (result.isTruncated) {
            result.warnings.add(
                'Results limited to ' + maxRows + ' rows (' + result.totalRowCount + ' total).'
            );
        }

        if (showGrandTotalRow && !parsed.grandTotals.isEmpty()) {
            result.grandTotal = buildGrandTotalRow(parsed, result.measures);
        }
    }

    private static CommissionReportResult.RepData buildRow(
        CommissionParsedReport parsed,
        String compositeKey
    ) {
        CommissionReportResult.RepData row = new CommissionReportResult.RepData();
        Map<String, Decimal> aggVals = parsed.valuesByKeyByAggregate.get(compositeKey);

        if (parsed.userGroupingOrdinal == 1) {
            String primaryK = '';
            String secondaryK = '';
            if (compositeKey.contains(KEY_SEPARATOR)) {
                List<String> parts = compositeKey.split('\\|\\|');
                primaryK = parts[0];
                secondaryK = parts.size() > 1 ? parts[1] : '';
            }
            row.userId = secondaryK;
            row.userName = parsed.secondLabelsByKey.get(compositeKey);
            row.contextKeyValue = primaryK;
            row.contextKeyLabel = parsed.labelsByKey.get(compositeKey);
        } else {
            row.userId = compositeKey;
            row.userName = parsed.labelsByKey.get(compositeKey);
        }

        row.keyValue = row.userId;
        row.keyLabel = row.userName;

        row.formattedValues.put(COL_USER_ID, row.userId != null ? row.userId : '');
        row.formattedValues.put(COL_USER_NAME, row.userName != null ? row.userName : '');
        if (parsed.dimensionCount == 2) {
            row.formattedValues.put(
                COL_CONTEXT,
                row.contextKeyLabel != null ? row.contextKeyLabel : ''
            );
        }

        for (CommissionReportResult.AggregateInfo agg : parsed.aggregates) {
            String colKey = 'agg_' + sanitizeKey(agg.key);
            Decimal v = aggVals != null ? aggVals.get(agg.key) : null;
            row.values.put(colKey, v);
            row.formattedValues.put(colKey, formatValue(v, agg.dataType));
        }

        return row;
    }

    private static CommissionReportResult.RepData buildGrandTotalRow(
        CommissionParsedReport parsed,
        List<CommissionReportResult.MeasureColumn> measures
    ) {
        CommissionReportResult.RepData row = new CommissionReportResult.RepData();
        row.isTotalRow = true;
        row.userName = 'Grand Total';
        row.keyLabel = 'Grand Total';
        row.formattedValues.put(COL_USER_ID, '');
        row.formattedValues.put(COL_USER_NAME, 'Grand Total');
        if (parsed.dimensionCount == 2) {
            row.formattedValues.put(COL_CONTEXT, '');
        }
        for (CommissionReportResult.MeasureColumn col : measures) {
            if (col.aggregateKey == null) {
                continue;
            }
            Decimal v = parsed.grandTotals.get(col.aggregateKey);
            row.values.put(col.key, v);
            row.formattedValues.put(col.key, formatValue(v, col.dataType));
        }
        return row;
    }

    private static String humanizeFieldName(String apiName) {
        if (String.isBlank(apiName)) {
            return 'Context';
        }
        String s = apiName.replace('__c', '').replace('.', ' ');
        return s;
    }

    private static String normalizeKey(Object keyValue) {
        if (keyValue == null) {
            return BLANK_KEY_TOKEN;
        }
        String keyStr = String.valueOf(keyValue).trim();
        if (String.isBlank(keyStr)) {
            return BLANK_KEY_TOKEN;
        }
        return keyStr;
    }

    private static String sanitizeKey(String key) {
        if (key == null) {
            return 'null';
        }
        return key.replace('!', '_').replace('.', '_').replace(' ', '_');
    }

    private static Decimal convertToDecimal(Object value) {
        if (value == null) {
            return null;
        }
        if (value instanceof Decimal) {
            return (Decimal) value;
        }
        if (value instanceof Integer) {
            return Decimal.valueOf((Integer) value);
        }
        if (value instanceof Long) {
            return Decimal.valueOf((Long) value);
        }
        if (value instanceof Double) {
            return Decimal.valueOf((Double) value);
        }
        try {
            return Decimal.valueOf(String.valueOf(value));
        } catch (Exception e) {
            return null;
        }
    }

    @TestVisible
    private static String formatValue(Decimal value, String dataType) {
        if (value == null) {
            return '—';
        }
        Integer decimals = 2;
        if (dataType == 'INT_DATA') {
            return formatWithCommas(value.setScale(0, RoundingMode.HALF_UP), 0);
        }
        if (dataType == 'CURRENCY_DATA') {
            String sym = UserInfo.getDefaultCurrency() == 'USD' ? '$' : '';
            return sym + formatWithCommas(value.setScale(decimals, RoundingMode.HALF_UP), decimals);
        }
        if (dataType == 'PERCENT_DATA') {
            return formatWithCommas((value * 100).setScale(decimals, RoundingMode.HALF_UP), decimals) + '%';
        }
        if (value == value.setScale(0)) {
            return formatWithCommas(value.setScale(0), 0);
        }
        return formatWithCommas(value.setScale(decimals, RoundingMode.HALF_UP), decimals);
    }

    private static String formatWithCommas(Decimal value, Integer decimalPlaces) {
        if (value == null) {
            return '—';
        }
        Boolean isNegative = value < 0;
        Decimal absValue = value.abs();
        Long integerPart = absValue.longValue();
        String integerStr = String.valueOf(integerPart);
        String out = '';
        Integer count = 0;
        for (Integer i = integerStr.length() - 1; i >= 0; i--) {
            if (count > 0 && Math.mod(count, 3) == 0) {
                out = ',' + out;
            }
            out = integerStr.substring(i, i + 1) + out;
            count++;
        }
        if (decimalPlaces > 0) {
            Decimal decimalPart = absValue - integerPart;
            String decimalStr = decimalPart.setScale(decimalPlaces, RoundingMode.HALF_UP).toPlainString();
            Integer dotIndex = decimalStr.indexOf('.');
            if (dotIndex >= 0) {
                out += decimalStr.substring(dotIndex);
            } else {
                out += '.' + '0'.repeat(decimalPlaces);
            }
        }
        return isNegative ? '-' + out : out;
    }

    private static String formatErrorMessage(Exception e) {
        if (e instanceof System.NoAccessException) {
            return 'You don\'t have access to this report.';
        }
        if (e.getMessage() != null) {
            String msg = e.getMessage();
            if (msg.contains('insufficient access')) {
                return 'You don\'t have access to run this report.';
            }
        }
        return 'An error occurred while running the report.';
    }
}