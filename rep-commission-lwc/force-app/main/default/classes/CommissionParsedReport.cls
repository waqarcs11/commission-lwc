/**
 * @description In-memory snapshot of a parsed Summary report (1-2 row groupings) for commission ingestion.
 */
public class CommissionParsedReport {
    public String reportId { get; set; }
    public String reportName { get; set; }
    public String groupingField { get; set; }
    public String secondGroupingField { get; set; }
    public Integer dimensionCount { get; set; }
    /** 0 = user is primary grouping only; 1 = user is inner (second) grouping. */
    public Integer userGroupingOrdinal { get; set; }
    /** API name of grouping that supplies User Id (primary or inner). */
    public String userGroupingFieldName { get; set; }
    public List<CommissionReportResult.AggregateInfo> aggregates { get; set; }
    public Map<String, Map<String, Decimal>> valuesByKeyByAggregate { get; set; }
    public Map<String, String> labelsByKey { get; set; }
    public Map<String, String> secondLabelsByKey { get; set; }
    public Map<String, Decimal> grandTotals { get; set; }
    public Boolean isValid { get; set; }
    public String errorMessage { get; set; }

    public CommissionParsedReport() {
        this.dimensionCount = 1;
        this.userGroupingOrdinal = 0;
        this.aggregates = new List<CommissionReportResult.AggregateInfo>();
        this.valuesByKeyByAggregate = new Map<String, Map<String, Decimal>>();
        this.labelsByKey = new Map<String, String>();
        this.secondLabelsByKey = new Map<String, String>();
        this.grandTotals = new Map<String, Decimal>();
        this.isValid = true;
    }
}