-- PIPELINE POINTS - September 2026 Contest Scoring Query
-- Pulls self-sourced SQL creation, stage progression, SAMPS demos, and weekly targets
-- Data sources: COHORTED_OPPORTUNITIES_PIPELINE, FACT_OPPORTUNITIES_REPORTING, SAMPS_ACTIVITIES, FACT_EMPLOYMENT_CURRENT
-- Run daily at 9 AM PT to refresh leaderboard
--
-- KEY NOTES:
-- 1. PROGRAM_SOURCE on COHORTED_OPPORTUNITIES_PIPELINE is NULL for Stage 2 rows.
--    Must join to FACT_OPPORTUNITIES_REPORTING to get PROGRAM_SOURCE = 'AE' for self-sourced.
-- 2. CITY values in FACT_EMPLOYMENT_CURRENT are metro-area labels like "NYC Metro (Remote)",
--    not exact city names. Use ILIKE for fuzzy matching.
-- 3. COUNTRY is "United States of America" not "US". Use ILIKE for matching.
-- 4. WEEK_START in COHORTED_OPPORTUNITIES_PIPELINE uses Saturday-start weeks.
--    Contest starts Aug 31 (Monday), so first WEEK_START is '2026-08-30' (Saturday).

-- ============================================================
-- 1. ROSTER: All active Field AEs with their managers and tier
-- ============================================================
WITH roster AS (
    SELECT
        ec.FULL_NAME,
        ec.DIRECT_LEAD AS MANAGER,
        ec.SFDC_OWNER_ID,
        ec.EMPLOYEE_ID,
        ec.CITY,
        ec.COUNTRY,
        CASE
            -- Tier 1: Major metros
            WHEN ec.CITY ILIKE '%Chicago%'
              OR ec.CITY ILIKE '%Dallas%'
              OR ec.CITY ILIKE '%Fort Worth%'
              OR ec.CITY ILIKE '%Fremont%'
              OR ec.CITY ILIKE '%Los Angeles%'
              OR ec.CITY ILIKE '%Miami%'
              OR ec.CITY ILIKE '%NYC%'
              OR ec.CITY ILIKE '%New York%'
              OR ec.CITY ILIKE '%San Francisco%'
              OR ec.CITY ILIKE '%San Jose%'
              OR ec.CITY ILIKE '%San Mateo%'
              OR ec.CITY ILIKE '%Toronto%'
              OR ec.CITY ILIKE '%Vancouver%'
              OR ec.CITY ILIKE '%Melbourne%'
              OR ec.CITY ILIKE '%Sydney%'
              OR ec.CITY ILIKE '%London%'
            THEN 1
            -- Tier 3: Smaller markets
            WHEN ec.CITY ILIKE '%Sacramento%'
              OR ec.CITY ILIKE '%Kansas City%'
              OR ec.CITY ILIKE '%Louisville%'
              OR ec.CITY ILIKE '%Memphis%'
              OR ec.CITY ILIKE '%Omaha%'
              OR ec.CITY ILIKE '%Boise%'
              OR ec.CITY ILIKE '%Charleston%'
              OR ec.CITY ILIKE '%Montreal%'
              OR ec.CITY ILIKE '%Montréal%'
              OR ec.CITY ILIKE '%Halifax%'
              OR ec.CITY ILIKE '%Gold Coast%'
              OR ec.CITY ILIKE '%Edinburgh%'
              OR ec.CITY ILIKE '%Glasgow%'
              OR ec.CITY ILIKE '%Belfast%'
              OR ec.CITY ILIKE '%Newcastle%'
              OR ec.CITY ILIKE '%Hobart%'
              OR ec.CITY ILIKE '%Kitchener%'
              OR ec.CITY ILIKE '%St. Catharines%'
              OR ec.CITY ILIKE '%Birmingham%'
              OR ec.CITY ILIKE '%Jackson%'
              OR ec.CITY ILIKE '%Oklahoma City%'
              OR ec.CITY ILIKE '%Spokane%'
              OR ec.CITY ILIKE '%Tucson%'
              OR ec.CITY ILIKE '%Virginia Beach%'
              OR ec.CITY ILIKE '%St. Louis%'
            THEN 3
            -- Tier 2: Everything else (mid-size markets + "Remote" + unmatched)
            ELSE 2
        END AS tier
    FROM APP_SALES.APP_SALES_ETL.FACT_EMPLOYMENT_CURRENT ec
    WHERE ec.MOST_RECENT = TRUE
      AND ec.ACTIVE_STATUS = 'Active'
      AND ec.SALES_TEAM_SFDC = 'Sales - US Field'
      AND ec.JOB_PROFILE_SET = 'Field Sales Account Executive'
      AND (ec.LAST_DAY_WORKED IS NULL OR ec.LAST_DAY_WORKED >= CURRENT_DATE())
      AND (ec.EMPLOYMENT_END_DATE IS NULL OR ec.EMPLOYMENT_END_DATE >= CURRENT_DATE())
),

-- ============================================================
-- 2. SQL CREATION POINTS: Self-sourced opps that become SQLs (Stage 2+)
--    Points based on GPV tier.
--    Join to FACT_OPPORTUNITIES_REPORTING for PROGRAM_SOURCE = 'AE'
-- ============================================================
sql_creation AS (
    SELECT
        cop.FULL_NAME,
        cop.OPPORTUNITY_ID,
        cop.TOTAL_ANNUAL_GPV_USD,
        cop.WEEK_START,
        CASE
            WHEN cop.TOTAL_ANNUAL_GPV_USD >= 2000000 THEN 3
            WHEN cop.TOTAL_ANNUAL_GPV_USD >= 1000000 THEN 2
            WHEN cop.TOTAL_ANNUAL_GPV_USD >= 500000 THEN 1
            ELSE 0
        END AS sql_points
    FROM APP_SALES.APP_SALES_ETL.COHORTED_OPPORTUNITIES_PIPELINE cop
    INNER JOIN APP_SALES.APP_SALES_ETL.FACT_OPPORTUNITIES_REPORTING fo
        ON cop.OPPORTUNITY_ID = fo.OPPORTUNITY_ID
    WHERE cop.SALES_TEAM = 'Sales - US Field'
      AND fo.PROGRAM_SOURCE = 'AE'
      AND cop.TOTAL_ANNUAL_GPV_USD >= 500000
      AND cop.MOVED_TO_STAGE_2_FINAL = 1
      AND cop.WEEK_START >= '2026-08-30'
      AND cop.WEEK_START <= '2026-09-30'
),

-- ============================================================
-- 3. SAMPS DEMO POINTS: +2 pts per completed SAMPS demo call
-- ============================================================
samps_demos AS (
    SELECT
        r.FULL_NAME,
        sa.TASK_ID,
        sa.ACTIVITY_DATE,
        sa.OPPORTUNITY_ID
    FROM APP_SALES.APP_SALES_ETL.SAMPS_ACTIVITIES sa
    JOIN APP_SALES.APP_SALES_ETL.FACT_OPPORTUNITIES_REPORTING fo
        ON sa.OPPORTUNITY_ID = fo.OPPORTUNITY_ID
    JOIN roster r
        ON fo.OWNER_ID = r.SFDC_OWNER_ID
    WHERE sa.IS_DEMO = 1
      AND sa.ACTIVITY_DATE >= '2026-08-31'
      AND sa.ACTIVITY_DATE <= '2026-09-30'
      AND sa.CALL_ANSWERED = 1
),

-- ============================================================
-- 4. WEEKLY SQL GPV: Sum of self-sourced SQL GPV per rep per week
--    Used for: +3 pts if hit weekly target, +5 pts if #1 on team
-- ============================================================
weekly_sql_gpv AS (
    SELECT
        cop.FULL_NAME,
        cop.CURRENT_MANAGER AS MANAGER,
        cop.WEEK_START,
        SUM(cop.TOTAL_ANNUAL_GPV_USD) AS weekly_gpv
    FROM APP_SALES.APP_SALES_ETL.COHORTED_OPPORTUNITIES_PIPELINE cop
    INNER JOIN APP_SALES.APP_SALES_ETL.FACT_OPPORTUNITIES_REPORTING fo
        ON cop.OPPORTUNITY_ID = fo.OPPORTUNITY_ID
    WHERE cop.SALES_TEAM = 'Sales - US Field'
      AND fo.PROGRAM_SOURCE = 'AE'
      AND cop.TOTAL_ANNUAL_GPV_USD >= 500000
      AND cop.MOVED_TO_STAGE_2_FINAL = 1
      AND cop.WEEK_START >= '2026-08-30'
      AND cop.WEEK_START <= '2026-09-30'
    GROUP BY 1, 2, 3
),

-- Weekly target hit: +3 pts
-- Tier 1 = $4.5M, Tier 2 = $4.0M, Tier 3 = $3.5M
weekly_target_hits AS (
    SELECT
        w.FULL_NAME,
        w.MANAGER,
        w.WEEK_START,
        w.weekly_gpv,
        r.tier,
        CASE
            WHEN r.tier = 1 AND w.weekly_gpv >= 4500000 THEN 3
            WHEN r.tier = 2 AND w.weekly_gpv >= 4000000 THEN 3
            WHEN r.tier = 3 AND w.weekly_gpv >= 3500000 THEN 3
            ELSE 0
        END AS target_points
    FROM weekly_sql_gpv w
    JOIN roster r ON w.FULL_NAME = r.FULL_NAME
),

-- Team #1 each week: +5 pts
weekly_team_winners AS (
    SELECT
        FULL_NAME,
        MANAGER,
        WEEK_START,
        weekly_gpv,
        ROW_NUMBER() OVER (PARTITION BY MANAGER, WEEK_START ORDER BY weekly_gpv DESC) AS team_rank
    FROM weekly_sql_gpv
),

team_winner_points AS (
    SELECT
        FULL_NAME,
        MANAGER,
        WEEK_START,
        CASE WHEN team_rank = 1 THEN 5 ELSE 0 END AS winner_points
    FROM weekly_team_winners
),

-- ============================================================
-- 5. AGGREGATE SCORING
-- ============================================================
sql_pts_agg AS (
    SELECT FULL_NAME, SUM(sql_points) AS total_sql_pts
    FROM sql_creation
    GROUP BY 1
),

demo_pts_agg AS (
    SELECT FULL_NAME, COUNT(DISTINCT TASK_ID) * 2 AS total_demo_pts
    FROM samps_demos
    GROUP BY 1
),

target_pts_agg AS (
    SELECT FULL_NAME, SUM(target_points) AS total_target_pts
    FROM weekly_target_hits
    GROUP BY 1
),

winner_pts_agg AS (
    SELECT FULL_NAME, SUM(winner_points) AS total_winner_pts
    FROM team_winner_points
    GROUP BY 1
)

-- ============================================================
-- FINAL LEADERBOARD
-- ============================================================
SELECT
    r.FULL_NAME,
    r.MANAGER,
    r.tier AS TIER,
    COALESCE(s.total_sql_pts, 0) AS SQL_CREATION_PTS,
    COALESCE(d.total_demo_pts, 0) AS SAMPS_DEMO_PTS,
    COALESCE(t.total_target_pts, 0) AS WEEKLY_TARGET_PTS,
    COALESCE(w.total_winner_pts, 0) AS TEAM_WINNER_PTS,
    (COALESCE(s.total_sql_pts, 0) +
     COALESCE(d.total_demo_pts, 0) +
     COALESCE(t.total_target_pts, 0) +
     COALESCE(w.total_winner_pts, 0)) AS TOTAL_POINTS
FROM roster r
LEFT JOIN sql_pts_agg s ON r.FULL_NAME = s.FULL_NAME
LEFT JOIN demo_pts_agg d ON r.FULL_NAME = d.FULL_NAME
LEFT JOIN target_pts_agg t ON r.FULL_NAME = t.FULL_NAME
LEFT JOIN winner_pts_agg w ON r.FULL_NAME = w.FULL_NAME
ORDER BY TOTAL_POINTS DESC, r.FULL_NAME ASC;
