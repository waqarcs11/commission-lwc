/**
 * @description One mapping row: which commission field to fill, which report, which report aggregate (matches MeasureColumn.aggregateKey).
 *              Align this with your CMDT or config store (same logical columns).
 */
public class CommissionMappingAttribute {
    @AuraEnabled public String targetFieldApiName { get; set; }
    @AuraEnabled public Id sourceReportId { get; set; }
    /** Report aggregate API key, e.g. RowCount or s!Amount — must match a MeasureColumn.aggregateKey on that report's result. */
    @AuraEnabled public String sourceAggregateKey { get; set; }

    public CommissionMappingAttribute() {
    }

    public CommissionMappingAttribute(String targetFieldApiName, Id sourceReportId, String sourceAggregateKey) {
        this.targetFieldApiName = targetFieldApiName;
        this.sourceReportId = sourceReportId;
        this.sourceAggregateKey = sourceAggregateKey;
    }
}