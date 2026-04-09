/**
 * @description Result of running a Summary report for commission ingestion: per-rep numbers, measure metadata, errors.
 *              Not a UI grid — use reps + values / formattedValues to map onto commission fields.
 */
public class CommissionReportResult {

    @AuraEnabled public List<MeasureColumn> measures { get; set; }
    @AuraEnabled public List<RepData> reps { get; set; }
    @AuraEnabled public RepData grandTotal { get; set; }
    @AuraEnabled public List<String> warnings { get; set; }
    @AuraEnabled public List<ReportError> errors { get; set; }
    @AuraEnabled public Integer totalRowCount { get; set; }
    @AuraEnabled public Boolean isTruncated { get; set; }
    @AuraEnabled public Map<String, String> reportNames { get; set; }
    @AuraEnabled public Long processingTimeMs { get; set; }
    @AuraEnabled public Boolean hasContextDimension { get; set; }
    @AuraEnabled public String contextGroupingFieldName { get; set; }
    @AuraEnabled public String userGroupingFieldApiName { get; set; }

    public CommissionReportResult() {
        this.measures = new List<MeasureColumn>();
        this.reps = new List<RepData>();
        this.warnings = new List<String>();
        this.errors = new List<ReportError>();
        this.totalRowCount = 0;
        this.isTruncated = false;
        this.hasContextDimension = false;
        this.reportNames = new Map<String, String>();
    }

    public class MeasureColumn {
        @AuraEnabled public String key { get; set; }
        @AuraEnabled public String label { get; set; }
        @AuraEnabled public String dataType { get; set; }
        @AuraEnabled public String reportId { get; set; }
        @AuraEnabled public String aggregateKey { get; set; }
        @AuraEnabled public Boolean isKeyColumn { get; set; }
        @AuraEnabled public String currencyCode { get; set; }
        @AuraEnabled public Integer customDecimals { get; set; }

        public MeasureColumn() {
            this.isKeyColumn = false;
            this.customDecimals = 2;
        }
    }

    public class RepData {
        @AuraEnabled public String userId { get; set; }
        @AuraEnabled public String userName { get; set; }
        @AuraEnabled public String contextKeyValue { get; set; }
        @AuraEnabled public String contextKeyLabel { get; set; }
        @AuraEnabled public String keyValue { get; set; }
        @AuraEnabled public String keyLabel { get; set; }
        @AuraEnabled public Map<String, Decimal> values { get; set; }
        @AuraEnabled public Map<String, String> formattedValues { get; set; }
        @AuraEnabled public Boolean isTotalRow { get; set; }

        public RepData() {
            this.values = new Map<String, Decimal>();
            this.formattedValues = new Map<String, String>();
            this.isTotalRow = false;
        }
    }

    public class ReportError {
        @AuraEnabled public String reportId { get; set; }
        @AuraEnabled public String reportName { get; set; }
        @AuraEnabled public String message { get; set; }
        @AuraEnabled public Boolean isFatal { get; set; }

        public ReportError() {
            this.isFatal = false;
        }

        public ReportError(String reportId, String message, Boolean isFatal) {
            this.reportId = reportId;
            this.message = message;
            this.isFatal = isFatal;
        }
    }

    public class AggregateInfo {
        public String key { get; set; }
        public String label { get; set; }
        public String dataType { get; set; }
        public Integer index { get; set; }

        public AggregateInfo(String key, String label, String dataType, Integer index) {
            this.key = key;
            this.label = label;
            this.dataType = dataType;
            this.index = index;
        }
    }
}