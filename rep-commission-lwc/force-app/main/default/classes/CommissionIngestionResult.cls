/**
 * @description Per-rep commission field values resolved from reports using CommissionMappingAttribute rows.
 */
public class CommissionIngestionResult {
    @AuraEnabled public List<RepIngestionRow> repRows { get; set; }
    @AuraEnabled public List<String> warnings { get; set; }
    @AuraEnabled public List<String> errors { get; set; }

    public CommissionIngestionResult() {
        this.repRows = new List<RepIngestionRow>();
        this.warnings = new List<String>();
        this.errors = new List<String>();
    }

    public class RepIngestionRow {
        /** 18-char User Id */
        @AuraEnabled public String userId { get; set; }
        /** targetFieldApiName from mapping → Decimal (measure) or null if missing */
        @AuraEnabled public Map<String, Object> fieldValues { get; set; }

        public RepIngestionRow() {
            this.fieldValues = new Map<String, Object>();
        }
    }
}