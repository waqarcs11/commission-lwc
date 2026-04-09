/**
 * @description Tests for CommissionResultsController (commission report runs).
 */
@IsTest
private class CommissionResultsControllerTest {

    private static Id testReportId() {
        return UserInfo.getUserId();
    }

    private static void registerParsed(Id reportId, CommissionParsedReport p) {
        CommissionResultsController.testParsedReportById = new Map<Id, CommissionParsedReport>{ reportId => p };
    }

    private static void registerParsed(Map<Id, CommissionParsedReport> byId) {
        CommissionResultsController.testParsedReportById = byId;
    }

    private static void clearParsed() {
        CommissionResultsController.testParsedReportById = null;
    }

    @IsTest
    static void testNullReportId() {
        CommissionReportResult result = CommissionResultsController.getCommissionReportData(null, 10, 'ALL', true);
        System.assertEquals(1, result.errors.size(), 'Expected fatal error');
        System.assert(result.errors[0].isFatal);
    }

    @IsTest
    static void testOneDimension_UserIdPrimary() {
        Id rid = testReportId();
        CommissionParsedReport p = buildOneDimParsed(rid);
        registerParsed(rid, p);
        try {
            CommissionReportResult result = CommissionResultsController.getCommissionReportData(
                rid,
                100,
                'ALL',
                true
            );
            System.assertEquals(0, result.errors.size(), String.valueOf(result.errors));
            System.assertEquals(2, result.reps.size());
            System.assertEquals(false, result.hasContextDimension);
            System.assertEquals('OwnerId', result.userGroupingFieldApiName);

            CommissionReportResult.RepData r0 = result.reps[0];
            System.assertEquals('005xx0000001', r0.userId);
            System.assertEquals('Alice Adams', r0.userName);
            System.assertEquals('005xx0000001', r0.keyValue);
            System.assertEquals('Alice Adams', r0.keyLabel);
            System.assertEquals('005xx0000001', r0.formattedValues.get(CommissionResultsController.COL_USER_ID));

            System.assert(result.measures[0].key == CommissionResultsController.COL_USER_ID);
            System.assert(result.measures[1].key == CommissionResultsController.COL_USER_NAME);

            System.assert(result.grandTotal != null);
            System.assertEquals(true, result.grandTotal.isTotalRow);
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testTwoDimensions_UserIdInner() {
        Id rid = testReportId();
        CommissionParsedReport p = buildTwoDimParsed(rid);
        registerParsed(rid, p);
        try {
            CommissionReportResult result = CommissionResultsController.getCommissionReportData(
                rid,
                100,
                'ALL',
                false
            );
            System.assertEquals(0, result.errors.size());
            System.assertEquals(true, result.hasContextDimension);
            System.assertEquals('STATUS', result.contextGroupingFieldName);
            System.assertEquals('Lead.Origin_Rep__c', result.userGroupingFieldApiName);

            CommissionReportResult.RepData r0 = result.reps[0];
            System.assertEquals('005Ug000009Nw69IAC', r0.userId);
            System.assertEquals('Ryan Goodman', r0.userName);
            System.assertEquals('Incomplete', r0.contextKeyLabel);
            System.assertEquals('Incomplete', r0.contextKeyValue);

            System.assert(result.measures.size() >= 4);
            System.assertEquals(CommissionResultsController.COL_CONTEXT, result.measures[2].key);
            System.assert(result.grandTotal == null);
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testMaxRowsTruncation() {
        Id rid = testReportId();
        CommissionParsedReport p = buildOneDimParsed(rid);
        registerParsed(rid, p);
        try {
            CommissionReportResult result = CommissionResultsController.getCommissionReportData(
                rid,
                1,
                'ALL',
                false
            );
            System.assertEquals(1, result.reps.size());
            System.assertEquals(true, result.isTruncated);
            System.assertEquals(2, result.totalRowCount);
            System.assert(!result.warnings.isEmpty());
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testFormatValueCurrency() {
        String s = CommissionResultsController.formatValue(Decimal.valueOf('1234.56'), 'CURRENCY_DATA');
        System.assert(s.contains('1'));
    }

    @IsTest
    static void testFormatValueNull() {
        String s = CommissionResultsController.formatValue(null, 'DOUBLE_DATA');
        System.assertEquals('—', s);
    }

    @IsTest
    static void testFormatValueIntAndPercent() {
        System.assertEquals('99', CommissionResultsController.formatValue(Decimal.valueOf(99), 'INT_DATA'));
        String pct = CommissionResultsController.formatValue(Decimal.valueOf('0.125'), 'PERCENT_DATA');
        System.assert(pct.contains('%'));
    }

    @IsTest
    static void testInvalidParsed_returnsError() {
        Id rid = testReportId();
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(rid);
        p.reportName = 'Bad';
        p.isValid = false;
        p.errorMessage = 'Not a summary report';
        registerParsed(rid, p);
        try {
            CommissionReportResult result = CommissionResultsController.getCommissionReportData(
                rid,
                100,
                'ALL',
                true
            );
            System.assertEquals(1, result.errors.size());
            System.assert(result.errors[0].isFatal);
            System.assertEquals('Not a summary report', result.errors[0].message);
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testOverload_defaultsAndMaxRowClamping() {
        Id rid = testReportId();
        CommissionParsedReport p = buildOneDimParsed(rid);
        registerParsed(rid, p);
        try {
            CommissionReportResult r0 = CommissionResultsController.getCommissionReportData(rid);
            System.assertEquals(2, r0.reps.size());
            System.assert(r0.grandTotal != null, 'Default showGrandTotalRow should be true');

            CommissionReportResult r1 = CommissionResultsController.getCommissionReportData(
                rid,
                0,
                'all',
                false
            );
            System.assertEquals(2, r1.reps.size(), 'maxRows < 1 should fall back to default cap');

            CommissionReportResult r2 = CommissionResultsController.getCommissionReportData(
                rid,
                CommissionResultsController.MAX_ROWS_CAP + 5000,
                'ALL',
                false
            );
            System.assertEquals(2, r2.reps.size());
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testGetCommissionDataForReportIds_twoDistinct() {
        Id idA = fakeReportId(1);
        Id idB = fakeReportId(2);

        registerParsed(
            new Map<Id, CommissionParsedReport>{
                idA => minimalOneDimParsed(idA, 'Report Alpha', '005xx0000001', 'User Alpha'),
                idB => minimalOneDimParsed(idB, 'Report Beta', '005xx0000002', 'User Beta')
            }
        );
        try {
            Map<Id, CommissionReportResult> byReport = CommissionResultsController.getCommissionDataForReportIds(
                new Set<Id>{ idA, idB }
            );
            System.assertEquals(2, byReport.size());
            System.assertEquals('Report Alpha', byReport.get(idA).reportNames.get(String.valueOf(idA)));
            System.assertEquals('Report Beta', byReport.get(idB).reportNames.get(String.valueOf(idB)));
            System.assertEquals('User Alpha', byReport.get(idA).reps[0].userName);
            System.assertEquals('User Beta', byReport.get(idB).reps[0].userName);
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testGetCommissionDataForReportIds_setDedupes() {
        Id idA = fakeReportId(3);

        registerParsed(
            new Map<Id, CommissionParsedReport>{
                idA => minimalOneDimParsed(idA, 'Report Gamma', '005xx0000003', 'User Gamma')
            }
        );
        try {
            Set<Id> withDup = new Set<Id>();
            withDup.add(idA);
            withDup.add(idA);
            System.assertEquals(1, withDup.size());

            Map<Id, CommissionReportResult> byReport = CommissionResultsController.getCommissionDataForReportIds(withDup);
            System.assertEquals(1, byReport.size());
            System.assertEquals(1, byReport.get(idA).reps.size());
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testGetCommissionDataForReportIds_listDedupes() {
        Id idA = fakeReportId(4);
        Id idB = fakeReportId(5);

        registerParsed(
            new Map<Id, CommissionParsedReport>{
                idA => minimalOneDimParsed(idA, 'R1', '005xx0000001', 'A'),
                idB => minimalOneDimParsed(idB, 'R2', '005xx0000002', 'B')
            }
        );
        try {
            List<Id> listWithDupes = new List<Id>{ idA, idA, idB, idA };
            Map<Id, CommissionReportResult> byReport = CommissionResultsController.getCommissionDataForReportIds(
                listWithDupes
            );
            System.assertEquals(2, byReport.size());
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testGetCommissionDataForReportIds_nullOrEmpty() {
        System.assertEquals(0, CommissionResultsController.getCommissionDataForReportIds((Set<Id>) null).size());
        System.assertEquals(0, CommissionResultsController.getCommissionDataForReportIds(new Set<Id>()).size());
        System.assertEquals(0, CommissionResultsController.getCommissionDataForReportIds((List<Id>) null).size());
        System.assertEquals(0, CommissionResultsController.getCommissionDataForReportIds(new List<Id>()).size());
    }

    @IsTest
    static void testBuildCommissionValues_emptyMapping() {
        CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForReps(null, new List<CommissionMappingAttribute>());
        System.assertEquals(1, ing.errors.size());
        System.assert(ing.repRows.isEmpty());
    }

    @IsTest
    static void testBuildCommissionValues_noSourceReportId() {
        List<CommissionMappingAttribute> maps = new List<CommissionMappingAttribute>{
            new CommissionMappingAttribute('Custom__c', null, 'RowCount')
        };
        CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForReps(null, maps);
        System.assertEquals(1, ing.errors.size());
    }

    @IsTest
    static void testBuildCommissionValues_twoAggregatesOneReport() {
        Id rid = testReportId();
        CommissionParsedReport p = buildOneDimTwoAggsParsed(rid);
        registerParsed(rid, p);
        try {
            List<CommissionMappingAttribute> maps = new List<CommissionMappingAttribute>{
                new CommissionMappingAttribute('Count__c', rid, 'RowCount'),
                new CommissionMappingAttribute('Amount__c', rid, 's!Amount')
            };
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForReps(null, maps);
            System.assertEquals(0, ing.errors.size(), String.valueOf(ing.errors));
            System.assertEquals(2, ing.repRows.size());
            CommissionIngestionResult.RepIngestionRow alice = ing.repRows[0];
            System.assertEquals('005xx0000001', alice.userId);
            System.assertEquals(Decimal.valueOf(5), (Decimal) alice.fieldValues.get('Count__c'));
            System.assertEquals(Decimal.valueOf(100), (Decimal) alice.fieldValues.get('Amount__c'));
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testBuildCommissionValues_nullRepIds_sortsAllReps() {
        Id rid = testReportId();
        registerParsed(rid, buildOneDimParsed(rid));
        try {
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForReps(
                null,
                new List<CommissionMappingAttribute>{ new CommissionMappingAttribute('X__c', rid, 'RowCount') }
            );
            System.assertEquals('005xx0000001', ing.repRows[0].userId);
            System.assertEquals('005xx0000002', ing.repRows[1].userId);
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testBuildCommissionValues_repIdsFiltersToCurrentUser() {
        Id rid = testReportId();
        Id me = UserInfo.getUserId();
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(rid);
        p.reportName = 'Solo';
        p.isValid = true;
        p.dimensionCount = 1;
        p.userGroupingOrdinal = 0;
        p.userGroupingFieldName = 'OwnerId';
        p.groupingField = 'OwnerId';
        p.aggregates.add(new CommissionReportResult.AggregateInfo('RowCount', 'Record Count', 'INT_DATA', 0));
        p.labelsByKey.put(String.valueOf(me), 'Me');
        p.valuesByKeyByAggregate.put(
            String.valueOf(me),
            new Map<String, Decimal>{ 'RowCount' => 42 }
        );
        p.grandTotals.put('RowCount', 42);
        registerParsed(rid, p);
        try {
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForReps(
                new List<Id>{ me },
                new List<CommissionMappingAttribute>{ new CommissionMappingAttribute('N__c', rid, 'RowCount') }
            );
            System.assertEquals(0, ing.errors.size(), String.valueOf(ing.errors));
            System.assertEquals(1, ing.repRows.size());
            System.assertEquals(String.valueOf(me), ing.repRows[0].userId);
            System.assertEquals(Decimal.valueOf(42), (Decimal) ing.repRows[0].fieldValues.get('N__c'));
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testBuildCommissionValues_twoReports() {
        Id idA = fakeReportId(6);
        Id idB = fakeReportId(7);
        registerParsed(
            new Map<Id, CommissionParsedReport>{
                idA => minimalOneDimParsed(idA, 'A', '005xx0000001', 'A'),
                idB => minimalOneDimParsed(idB, 'B', '005xx0000002', 'B')
            }
        );
        try {
            List<CommissionMappingAttribute> maps = new List<CommissionMappingAttribute>{
                new CommissionMappingAttribute('FromA__c', idA, 'RowCount'),
                new CommissionMappingAttribute('FromB__c', idB, 'RowCount')
            };
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForReps(null, maps);
            System.assertEquals(0, ing.errors.size(), String.valueOf(ing.errors));
            System.assertEquals(2, ing.repRows.size());
            Map<String, CommissionIngestionResult.RepIngestionRow> byUser = new Map<String, CommissionIngestionResult.RepIngestionRow>();
            for (CommissionIngestionResult.RepIngestionRow row : ing.repRows) {
                byUser.put(row.userId, row);
            }
            System.assertEquals(Decimal.valueOf(1), (Decimal) byUser.get('005xx0000001').fieldValues.get('FromA__c'));
            System.assertEquals(null, byUser.get('005xx0000001').fieldValues.get('FromB__c'));
            System.assertEquals(null, byUser.get('005xx0000002').fieldValues.get('FromA__c'));
            System.assertEquals(Decimal.valueOf(1), (Decimal) byUser.get('005xx0000002').fieldValues.get('FromB__c'));
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testBuildCommissionValues_invalidReportAddsError() {
        Id rid = testReportId();
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(rid);
        p.reportName = 'Bad';
        p.isValid = false;
        p.errorMessage = 'Not a summary report';
        registerParsed(rid, p);
        try {
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForReps(
                null,
                new List<CommissionMappingAttribute>{ new CommissionMappingAttribute('X__c', rid, 'RowCount') }
            );
            System.assertEquals(1, ing.errors.size());
            System.assert(ing.errors[0].contains('Not a summary report'));
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testBuildCommissionValuesByLabel_twoReports() {
        Id idA = fakeReportId(8);
        Id idB = fakeReportId(9);
        registerParsed(
            new Map<Id, CommissionParsedReport>{
                idA => minimalOneDimParsed(idA, 'A', '005xx0000001', 'A'),
                idB => minimalOneDimParsed(idB, 'B', '005xx0000002', 'B')
            }
        );
        try {
            List<CommissionFieldMappingRequest> maps = new List<CommissionFieldMappingRequest>{
                new CommissionFieldMappingRequest('FromA__c', idA, 'Record Count', 'COUNT'),
                new CommissionFieldMappingRequest('FromB__c', idB, 'Record Count', null)
            };
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForRepsByLabel(
                null,
                maps
            );
            System.assertEquals(0, ing.errors.size(), String.valueOf(ing.errors));
            System.assertEquals(2, ing.repRows.size());
            Map<String, CommissionIngestionResult.RepIngestionRow> byUser = new Map<String, CommissionIngestionResult.RepIngestionRow>();
            for (CommissionIngestionResult.RepIngestionRow row : ing.repRows) {
                byUser.put(row.userId, row);
            }
            System.assertEquals(Decimal.valueOf(1), (Decimal) byUser.get('005xx0000001').fieldValues.get('FromA__c'));
            System.assertEquals(null, byUser.get('005xx0000001').fieldValues.get('FromB__c'));
            System.assertEquals(null, byUser.get('005xx0000002').fieldValues.get('FromA__c'));
            System.assertEquals(Decimal.valueOf(1), (Decimal) byUser.get('005xx0000002').fieldValues.get('FromB__c'));
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testBuildCommissionValuesByLabel_missingLabelAddsError() {
        Id rid = testReportId();
        registerParsed(rid, buildOneDimTwoAggsParsed(rid));
        try {
            List<CommissionFieldMappingRequest> maps = new List<CommissionFieldMappingRequest>{
                new CommissionFieldMappingRequest('Missing__c', rid, 'Not A Real Label', null)
            };
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForRepsByLabel(
                null,
                maps
            );
            System.assertEquals(1, ing.errors.size());
            System.assert(ing.errors[0].contains('could not resolve sourceFieldLabel'));
            System.assertEquals(2, ing.repRows.size(), 'Rows still return with null mapping values');
            System.assertEquals(null, ing.repRows[0].fieldValues.get('Missing__c'));
        } finally {
            clearParsed();
        }
    }

    @IsTest
    static void testBuildCommissionValuesByLabel_ambiguousLabelWithoutAggregateType() {
        Id rid = testReportId();
        registerParsed(rid, buildOneDimAmbiguousLabelParsed(rid));
        try {
            List<CommissionFieldMappingRequest> maps = new List<CommissionFieldMappingRequest>{
                new CommissionFieldMappingRequest('Ambiguous__c', rid, 'Deal Margin', null)
            };
            CommissionIngestionResult ing = CommissionResultsController.buildCommissionValuesForRepsByLabel(
                null,
                maps
            );
            System.assertEquals(1, ing.errors.size());
            System.assert(ing.errors[0].contains('ambiguous'));
            System.assertEquals(null, ing.repRows[0].fieldValues.get('Ambiguous__c'));
        } finally {
            clearParsed();
        }
    }

    // --- helpers ---

    private static CommissionParsedReport buildOneDimParsed(Id reportId) {
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(reportId);
        p.reportName = 'Test 1D';
        p.isValid = true;
        p.dimensionCount = 1;
        p.userGroupingOrdinal = 0;
        p.userGroupingFieldName = 'OwnerId';
        p.groupingField = 'OwnerId';
        p.aggregates.add(new CommissionReportResult.AggregateInfo('RowCount', 'Record Count', 'INT_DATA', 0));

        addRow(p, '005xx0000001', 'Alice Adams', 5);
        addRow(p, '005xx0000002', 'Bob Baker', 3);
        p.grandTotals.put('RowCount', 8);
        return p;
    }

    private static CommissionParsedReport buildTwoDimParsed(Id reportId) {
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(reportId);
        p.reportName = 'My Leads';
        p.isValid = true;
        p.dimensionCount = 2;
        p.userGroupingOrdinal = 1;
        p.userGroupingFieldName = 'Lead.Origin_Rep__c';
        p.groupingField = 'STATUS';
        p.secondGroupingField = 'Lead.Origin_Rep__c';
        p.aggregates.add(new CommissionReportResult.AggregateInfo('RowCount', 'Record Count', 'INT_DATA', 0));

        String ck = 'Incomplete||005Ug000009Nw69IAC';
        p.labelsByKey.put(ck, 'Incomplete');
        p.secondLabelsByKey.put(ck, 'Ryan Goodman');
        p.valuesByKeyByAggregate.put(ck, new Map<String, Decimal>{ 'RowCount' => 7 });
        p.grandTotals.put('RowCount', 7);
        return p;
    }

    private static void addRow(
        CommissionParsedReport p,
        String userId,
        String userName,
        Integer rowCount
    ) {
        p.labelsByKey.put(userId, userName);
        p.valuesByKeyByAggregate.put(userId, new Map<String, Decimal>{ 'RowCount' => Decimal.valueOf(rowCount) });
    }

    private static CommissionParsedReport buildOneDimTwoAggsParsed(Id reportId) {
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(reportId);
        p.reportName = 'Test 1D two aggs';
        p.isValid = true;
        p.dimensionCount = 1;
        p.userGroupingOrdinal = 0;
        p.userGroupingFieldName = 'OwnerId';
        p.groupingField = 'OwnerId';
        p.aggregates.add(new CommissionReportResult.AggregateInfo('RowCount', 'Record Count', 'INT_DATA', 0));
        p.aggregates.add(new CommissionReportResult.AggregateInfo('s!Amount', 'Sum of Amount', 'CURRENCY_DATA', 1));
        addRowTwoAggs(p, '005xx0000001', 'Alice Adams', 5, Decimal.valueOf(100));
        addRowTwoAggs(p, '005xx0000002', 'Bob Baker', 3, Decimal.valueOf(200));
        p.grandTotals.put('RowCount', 8);
        p.grandTotals.put('s!Amount', 300);
        return p;
    }

    private static CommissionParsedReport buildOneDimAmbiguousLabelParsed(Id reportId) {
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(reportId);
        p.reportName = 'Test ambiguous labels';
        p.isValid = true;
        p.dimensionCount = 1;
        p.userGroupingOrdinal = 0;
        p.userGroupingFieldName = 'OwnerId';
        p.groupingField = 'OwnerId';
        p.aggregates.add(new CommissionReportResult.AggregateInfo('s!DealMargin', 'Deal Margin', 'CURRENCY_DATA', 0));
        p.aggregates.add(new CommissionReportResult.AggregateInfo('a!DealMargin', 'Deal Margin', 'DOUBLE_DATA', 1));
        p.labelsByKey.put('005xx0000001', 'Alice Adams');
        p.valuesByKeyByAggregate.put(
            '005xx0000001',
            new Map<String, Decimal>{
                's!DealMargin' => Decimal.valueOf(120),
                'a!DealMargin' => Decimal.valueOf(60)
            }
        );
        p.grandTotals.put('s!DealMargin', 120);
        p.grandTotals.put('a!DealMargin', 60);
        return p;
    }

    private static void addRowTwoAggs(
        CommissionParsedReport p,
        String userId,
        String userName,
        Integer rowCount,
        Decimal amount
    ) {
        p.labelsByKey.put(userId, userName);
        p.valuesByKeyByAggregate.put(
            userId,
            new Map<String, Decimal>{
                'RowCount' => Decimal.valueOf(rowCount),
                's!Amount' => amount
            }
        );
    }

    private static CommissionParsedReport minimalOneDimParsed(
        Id reportId,
        String reportName,
        String userId,
        String userName
    ) {
        CommissionParsedReport p = new CommissionParsedReport();
        p.reportId = String.valueOf(reportId);
        p.reportName = reportName;
        p.isValid = true;
        p.dimensionCount = 1;
        p.userGroupingOrdinal = 0;
        p.userGroupingFieldName = 'OwnerId';
        p.groupingField = 'OwnerId';
        p.aggregates.add(new CommissionReportResult.AggregateInfo('RowCount', 'Record Count', 'INT_DATA', 0));
        p.labelsByKey.put(userId, userName);
        p.valuesByKeyByAggregate.put(userId, new Map<String, Decimal>{ 'RowCount' => 1 });
        p.grandTotals.put('RowCount', 1);
        return p;
    }

    private static Id fakeReportId(Integer seed) {
        String body = String.valueOf(seed).leftPad(12, '0');
        return (Id) ('00O' + body);
    }
}