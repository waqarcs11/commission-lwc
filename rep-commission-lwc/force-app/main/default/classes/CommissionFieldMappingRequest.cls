/**
 * @description Label-driven mapping row used for metadata-based ingestion.
 *              A caller provides the target commission field, source report, and source field label from report metadata.
 */
public class CommissionFieldMappingRequest {
    @AuraEnabled public String targetFieldApiName { get; set; }
    @AuraEnabled public Id sourceReportId { get; set; }
    /**
     * Human label from the report measure, e.g. "Record Count", "Sum of Funded Amount", "Average of Points".
     */
    @AuraEnabled public String sourceFieldLabel { get; set; }
    /**
     * Optional disambiguator for duplicate labels: SUM | AVG | MIN | MAX | COUNT.
     */
    @AuraEnabled public String preferredAggregateType { get; set; }

    public CommissionFieldMappingRequest() {
    }

    public CommissionFieldMappingRequest(
        String targetFieldApiName,
        Id sourceReportId,
        String sourceFieldLabel,
        String preferredAggregateType
    ) {
        this.targetFieldApiName = targetFieldApiName;
        this.sourceReportId = sourceReportId;
        this.sourceFieldLabel = sourceFieldLabel;
        this.preferredAggregateType = preferredAggregateType;
    }
}