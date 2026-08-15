-- ============================================================
-- CREDIT CARD LOAN PORTFOLIO — RISK ANALYSIS V2
-- Multi-Table SQL Analysis (Customers × Loans × Payments)
-- ============================================================

-- ============================================================
-- STEP 1: DATA CLEANING (documented in cleaning script)
-- Issues resolved before analysis:
--   • 500 duplicate customers removed
--   • 6,054 string incomes cleaned ($XX,XXX → numeric)
--   • 1,007 invalid credit scores fixed (0, -1, 999 → median)
--   • 29 purpose variants standardized → 8 categories
--   • 3 date formats parsed → unified datetime
--   • 361,835 payments aggregated → loan-level summaries
-- ============================================================


-- 1. PORTFOLIO OVERVIEW (multi-table JOIN)
SELECT
    COUNT(DISTINCT l.loan_id)                   AS total_loans,
    COUNT(DISTINCT l.customer_id)               AS unique_borrowers,
    ROUND(AVG(l.loan_amount), 0)                AS avg_loan_amount,
    ROUND(SUM(l.loan_amount), 0)                AS total_exposure,
    ROUND(AVG(l.interest_rate), 2)              AS avg_interest_rate,
    ROUND(AVG(c.credit_score), 0)               AS avg_credit_score,
    SUM(l.defaulted)                            AS total_defaults,
    ROUND(AVG(l.defaulted) * 100, 1)            AS default_rate_pct
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id;


-- 2. DEFAULT RATE BY INCOME BRACKET (with loss severity)
SELECT
    c.income_bracket,
    COUNT(*)                                    AS loan_count,
    SUM(l.defaulted)                            AS defaults,
    ROUND(AVG(l.defaulted) * 100, 1)            AS default_rate_pct,
    ROUND(SUM(l.loan_amount), 0)                AS total_exposure,
    ROUND(SUM(CASE WHEN l.defaulted=1 THEN l.loan_amount ELSE 0 END), 0)
                                                AS loss_exposure,
    ROUND(SUM(CASE WHEN l.defaulted=1 THEN l.loan_amount ELSE 0 END) * 100.0
          / SUM(l.loan_amount), 1)              AS loss_share_pct,
    ROUND(AVG(c.credit_score), 0)               AS avg_credit_score
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY c.income_bracket
ORDER BY default_rate_pct DESC;


-- 3. CREDIT UTILIZATION BUCKETS
-- KEY FINDING: >70% utilization = 32.5% default (5.4x the <30% bucket)
SELECT
    l.utilization_bucket,
    COUNT(*)                                    AS loan_count,
    SUM(l.defaulted)                            AS defaults,
    ROUND(AVG(l.defaulted) * 100, 1)            AS default_rate_pct,
    ROUND(AVG(l.loan_amount), 0)                AS avg_loan_amount,
    ROUND(AVG(c.credit_score), 0)               AS avg_credit_score
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY l.utilization_bucket
ORDER BY l.utilization_bucket;


-- 4. HIGH-RISK CROSS-SEGMENT: Income × Utilization
-- KEY FINDING: Low income + high utilization = 22-27% default
SELECT
    c.income_bracket,
    CASE
        WHEN l.credit_utilization < 0.50 THEN 'Low Util (<50%)'
        ELSE 'High Util (50%+)'
    END AS util_group,
    COUNT(*)                                    AS loan_count,
    ROUND(AVG(l.defaulted) * 100, 1)            AS default_rate_pct,
    ROUND(SUM(l.loan_amount), 0)                AS total_exposure,
    ROUND(SUM(CASE WHEN l.defaulted=1 THEN l.loan_amount ELSE 0 END), 0)
                                                AS loss_amount
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY c.income_bracket, util_group
ORDER BY default_rate_pct DESC;


-- 5. DELINQUENCY HISTORY IMPACT
SELECT
    CASE
        WHEN l.num_delinquencies_2yr = 0 THEN '0 (Clean)'
        WHEN l.num_delinquencies_2yr = 1 THEN '1'
        WHEN l.num_delinquencies_2yr = 2 THEN '2'
        ELSE '3+'
    END AS delinquency_group,
    COUNT(*)                                    AS loan_count,
    ROUND(AVG(l.defaulted) * 100, 1)            AS default_rate_pct,
    ROUND(AVG(c.credit_score), 0)               AS avg_credit_score,
    ROUND(AVG(l.credit_utilization) * 100, 1)   AS avg_utilization_pct
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY delinquency_group
ORDER BY delinquency_group;


-- 6. PAYMENT BEHAVIOR vs DEFAULT (3-table JOIN)
SELECT
    CASE
        WHEN p.miss_rate = 0 THEN '0% Missed'
        WHEN p.miss_rate < 0.10 THEN '1-10% Missed'
        WHEN p.miss_rate < 0.20 THEN '10-20% Missed'
        ELSE '20%+ Missed'
    END AS payment_group,
    COUNT(*)                                    AS loan_count,
    ROUND(AVG(l.defaulted) * 100, 1)            AS default_rate_pct,
    ROUND(AVG(p.total_paid), 0)                 AS avg_total_paid,
    ROUND(AVG(l.loan_amount), 0)                AS avg_loan_amount
FROM loans l
JOIN payment_summary p ON l.loan_id = p.loan_id
GROUP BY payment_group
ORDER BY payment_group;


-- 7. WINDOW FUNCTION — Rank purposes by risk within each income bracket
SELECT
    income_bracket,
    purpose,
    loan_count,
    default_rate_pct,
    RANK() OVER (
        PARTITION BY income_bracket
        ORDER BY default_rate_pct DESC
    ) AS risk_rank
FROM (
    SELECT
        c.income_bracket,
        l.purpose,
        COUNT(*)                            AS loan_count,
        ROUND(AVG(l.defaulted) * 100, 1)    AS default_rate_pct
    FROM loans l
    JOIN customers c ON l.customer_id = c.customer_id
    GROUP BY c.income_bracket, l.purpose
    HAVING COUNT(*) >= 100
)
ORDER BY income_bracket, risk_rank;


-- 8. LOAN GRADE ANALYSIS
SELECT
    l.grade,
    COUNT(*)                                    AS loan_count,
    ROUND(AVG(l.defaulted) * 100, 1)            AS default_rate_pct,
    ROUND(AVG(l.interest_rate), 2)              AS avg_rate,
    ROUND(AVG(l.loan_amount), 0)                AS avg_loan_size,
    ROUND(AVG(c.credit_score), 0)               AS avg_credit_score
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id
GROUP BY l.grade
ORDER BY l.grade;


-- 9. RISK SCORECARD (weighted CASE scoring model)
-- Score 0-100: Credit Score (0-30) + Utilization (0-25)
--              + Delinquencies (0-25) + DTI (0-20)
SELECT
    l.loan_id,
    c.customer_id,
    c.credit_score,
    l.credit_utilization,
    l.num_delinquencies_2yr,
    l.dti,
    l.grade,
    ROUND(
        (CASE WHEN c.credit_score < 580 THEN 30
              WHEN c.credit_score < 650 THEN 20
              WHEN c.credit_score < 720 THEN 10
              ELSE 0 END)
      + (CASE WHEN l.credit_utilization > 0.70 THEN 25
              WHEN l.credit_utilization > 0.50 THEN 15
              WHEN l.credit_utilization > 0.30 THEN 5
              ELSE 0 END)
      + (CASE WHEN l.num_delinquencies_2yr >= 3 THEN 25
              WHEN l.num_delinquencies_2yr >= 1 THEN 10
              ELSE 0 END)
      + (CASE WHEN l.dti > 0.50 THEN 20
              WHEN l.dti > 0.35 THEN 10
              ELSE 0 END)
    , 0) AS risk_score,
    l.defaulted AS actual_default
FROM loans l
JOIN customers c ON l.customer_id = c.customer_id;


-- 10. SCORECARD VALIDATION — proves the model works
-- Result: monotonic increase from 2.1% → 43.5% across bands
SELECT
    CASE
        WHEN risk_score < 20 THEN '0-19 (Low)'
        WHEN risk_score < 40 THEN '20-39'
        WHEN risk_score < 60 THEN '40-59'
        WHEN risk_score < 80 THEN '60-79'
        ELSE '80-100 (High)'
    END AS score_band,
    COUNT(*) AS loan_count,
    SUM(actual_default) AS defaults,
    ROUND(AVG(actual_default) * 100, 1) AS default_rate_pct,
    ROUND(SUM(loan_amount), 0) AS total_exposure
FROM (
    SELECT
        l.loan_id, l.loan_amount,
        ROUND(
            (CASE WHEN c.credit_score < 580 THEN 30
                  WHEN c.credit_score < 650 THEN 20
                  WHEN c.credit_score < 720 THEN 10
                  ELSE 0 END)
          + (CASE WHEN l.credit_utilization > 0.70 THEN 25
                  WHEN l.credit_utilization > 0.50 THEN 15
                  WHEN l.credit_utilization > 0.30 THEN 5
                  ELSE 0 END)
          + (CASE WHEN l.num_delinquencies_2yr >= 3 THEN 25
                  WHEN l.num_delinquencies_2yr >= 1 THEN 10
                  ELSE 0 END)
          + (CASE WHEN l.dti > 0.50 THEN 20
                  WHEN l.dti > 0.35 THEN 10
                  ELSE 0 END)
        , 0) AS risk_score,
        l.defaulted AS actual_default
    FROM loans l
    JOIN customers c ON l.customer_id = c.customer_id
)
GROUP BY score_band
ORDER BY score_band;
