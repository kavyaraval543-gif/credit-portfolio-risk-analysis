# Credit Card Loan Portfolio — Risk Analysis

A business analyst project analyzing a **150,000-loan credit card portfolio** across 50,000 customers and 360,000 payment records to identify default drivers, build a risk scorecard, and recommend underwriting changes projected to reduce portfolio losses by ~$60M.

Built with **SQL** (multi-table JOINs, window functions, CASE-based scoring) and **Excel** (dashboard with charts, conditional formatting, data bars).

---

## Key Findings

| Metric | Value |
|---|---|
| Portfolio Size | 149,800 loans · $1.98B exposure |
| Overall Default Rate | 11.6% |
| Highest-Risk Segment | Utilization >70% → **32.5% default** (5.4× portfolio avg) |
| Scorecard Accuracy | Monotonic: 2.1% (low risk) → 43.5% (high risk) |

**Credit utilization is the strongest predictor of default.** Borrowers above 70% utilization default at 32.5% — over five times the rate of those under 30% (6.0%). When combined with past delinquencies (3+), the default rate reaches 30.6%.

**The risk scorecard validates cleanly.** A simple weighted model using four variables (credit score, utilization, delinquencies, DTI) produces score bands with default rates rising from 2.1% to 43.5% — strong discriminatory power without needing machine learning.

**Loan purpose has almost no predictive value** (10.8–11.9% range across all categories). Default risk is borrower-driven, not purpose-driven.

---

## Project Structure

```
├── README.md
├── raw_customers.csv            # 50,500 rows (messy — duplicates, string formats, invalid values)
├── raw_loans.csv                # 150,000 rows (messy — mixed date formats, inconsistent categories)
├── raw_payments.csv             # 361,835 rows (raw payment-level records)
├── portfolio_analysis_v2.sql    # 10 production SQL queries with comments
└── Credit_Card_Portfolio_Risk_Analysis_V2.xlsx
    ├── Executive Summary        # KPIs, key findings, recommendations
    ├── Segment Analysis         # Default rates by income, purpose, age, grade (with charts)
    ├── Risk Deep Dive           # Utilization buckets, delinquency impact, cross-segments
    ├── Scorecard Validation     # Model validation with monotonic default rate proof
    ├── Vintage Cohort           # Year-over-year trends, state-level analysis
    ├── Data Cleaning Log        # 13 documented cleaning steps
    └── SQL Queries              # Key query snippets for reference
```

---

## Data Pipeline

### 1. Raw Data (3 Tables — Intentionally Messy)

The raw dataset simulates real-world data quality issues commonly found in bank systems:

| Table | Rows | Issues |
|---|---|---|
| `raw_customers` | 50,500 | 500 duplicate IDs, 6,054 incomes as strings (`$45,000`), 1,007 invalid credit scores (0, -1, 999), mixed state formats (`CA` vs `California` vs `ca`), employment length as text (`3 years`, `< 1 year`, `10+ years`) |
| `raw_loans` | 150,000 | 200 null loan amounts, 12,136 interest rates as strings (`12.5%`), 29 inconsistent purpose labels, 3 mixed date formats (ISO/US/EU) |
| `raw_payments` | 361,835 | Raw payment-level records needing aggregation to loan level |

### 2. Data Cleaning (13 Steps)

Every cleaning decision is documented and reproducible:

- Deduplicated customers on `customer_id`
- Stripped `$` and commas from income strings → numeric; imputed missing with median
- Clamped invalid credit scores → replaced with median (679)
- Standardized state codes (full names → abbreviations, consistent casing)
- Regex-parsed employment length strings → numeric years
- Dropped 200 loans with null amounts (0.13% of data)
- Standardized 29 purpose variants → 8 canonical categories
- Parsed 3 date formats → unified datetime
- Aggregated 361K payment records → loan-level summaries (missed payments, miss rate)

### 3. SQL Analysis (Multi-Table JOINs)

All analysis queries use JOINs across the three cleaned tables. Key techniques demonstrated:

**Cross-table JOINs** — every query joins `loans` to `customers`; payment analysis adds a third table:
```sql
SELECT ...
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
LEFT JOIN payment_summary p ON l.loan_id = p.loan_id
```

**Window functions** — ranking loan purposes by default rate within each income bracket:
```sql
RANK() OVER (
    PARTITION BY income_bracket
    ORDER BY default_rate_pct DESC
) AS risk_rank
```

**CASE-based risk scorecard** — weighted scoring model using four variables:
```sql
(CASE WHEN credit_score < 580 THEN 30
      WHEN credit_score < 650 THEN 20
      WHEN credit_score < 720 THEN 10
      ELSE 0 END)
+ (CASE WHEN credit_utilization > 0.70 THEN 25
        WHEN credit_utilization > 0.50 THEN 15
        WHEN credit_utilization > 0.30 THEN 5
        ELSE 0 END)
+ ...
AS risk_score
```

### 4. Risk Scorecard Validation

The scorecard assigns each loan a 0–100 risk score based on four weighted factors:

| Factor | Low Risk | Medium | High Risk |
|---|---|---|---|
| Credit Score | 720+ → 0 pts | 650–719 → 10 pts | <580 → 30 pts |
| Utilization | <30% → 0 pts | 30–50% → 5 pts | >70% → 25 pts |
| Delinquencies | 0 → 0 pts | 1–2 → 10 pts | 3+ → 25 pts |
| Debt-to-Income | <35% → 0 pts | 35–50% → 10 pts | >50% → 20 pts |

**Validation result:**

| Score Band | Loans | Default Rate |
|---|---|---|
| 0–19 (Low) | 512 | **2.1%** |
| 20–39 | 58,150 | **5.5%** |
| 40–59 | 73,230 | **12.3%** |
| 60–79 | 15,613 | **26.5%** |
| 80–100 (High) | 2,295 | **43.5%** |

Default rates increase monotonically across all bands — the model has strong discriminatory power without requiring machine learning.

---

## Recommendation

Tighten approval criteria for borrowers with **utilization >50% AND delinquencies ≥2**. This segment represents ~12% of loans but ~28% of total losses. Implementing the risk scorecard (flag score ≥60 for manual review) is projected to reduce portfolio losses by approximately **$60M** while sacrificing only ~12% of loan volume.

---

## Tools Used

- **SQL** (SQLite) — multi-table JOINs, window functions, CASE expressions, aggregate functions, subqueries
- **Excel** — pivot-style dashboard, bar/line charts, conditional formatting with data bars, color-coded risk scores
- **Python** (pandas, openpyxl) — data generation, cleaning pipeline, dashboard automation

---

## How to Run

```bash
# Load the raw CSVs into any SQL database (SQLite, PostgreSQL, MySQL)
sqlite3 portfolio.db
.mode csv
.import raw_customers.csv raw_customers
.import raw_loans.csv raw_loans
.import raw_payments.csv raw_payments

# Run the analysis queries
.read portfolio_analysis_v2.sql
```

Or open the Excel dashboard directly — all results are pre-computed in the workbook.

---

## About

This project was built as a portfolio piece for business analyst and product management roles. The dataset is synthetic (generated with realistic statistical distributions) but the analysis methodology, SQL patterns, and business recommendations mirror real-world credit risk work.

**Author:** Kavya Raval
**Institution:** NMIMS University, Mumbai — BTech Electrical, Electronics & Communications Engineering
