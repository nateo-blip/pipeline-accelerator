-- PIPELINE POINTS - September 2026 Contest Scoring Query
-- Pulls self-sourced SQL creation, stage progression, SAMPS demos, and weekly targets
-- Data sources: COHORTED_OPPORTUNITIES_PIPELINE, SAMPS_ACTIVITIES, FACT_EMPLOYMENT_CURRENT
-- Run daily at 9 AM PT to refresh leaderboard

-- Contest dates
SET contest_start = '2026-09-01';
SET contest_end = '2026-09-30';

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
            -- Tier 1 - US
            WHEN ec.COUNTRY = 'US' AND ec.CITY IN ('Chicago','Dallas','Fort Worth','Fremont','Los Angeles','Miami','New York City','San Francisco','San Jose','San Mateo') THEN 1
            -- Tier 1 - CA
            WHEN ec.COUNTRY = 'CA' AND ec.CITY IN ('Toronto','Vancouver') THEN 1
            -- Tier 1 - AU
            WHEN ec.COUNTRY = 'AU' AND ec.CITY IN ('Melbourne','Sydney') THEN 1
            -- Tier 1 - GB
            WHEN ec.COUNTRY = 'GB' AND ec.CITY IN ('London') THEN 1
            -- Tier 2 - US
            WHEN ec.COUNTRY = 'US' AND ec.CITY IN ('Atlanta','Austin','Baltimore','Boston','Charlotte','Cincinnati','Cleveland','Columbus','Denver','Detroit','Fort Lauderdale','Hackensack','Honolulu','Houston','Indianapolis','Jacksonville','Jersey City','Las Vegas','Long Beach','Long Island','Milwaukee','Minneapolis','Morristown','Nashville','New Orleans','Newark','Orange County','Orlando','Philadelphia','Phoenix','Pittsburgh','Portland','Raleigh','Salt Lake City','San Antonio','San Diego','San Fernando Valley','San Gabriel Valley','Santa Clarita','Seattle','Somerset County','St. Louis','Tampa','Trenton','Ventura County','Washington','West Palm Beach','Westchester County') THEN 2
            -- Tier 2 - CA
            WHEN ec.COUNTRY = 'CA' AND ec.CITY IN ('Calgary','East York','Edmonton','Hamilton','Mississauga','North York','Ottawa','Richmond','Winnipeg') THEN 2
            -- Tier 2 - AU
            WHEN ec.COUNTRY = 'AU' AND ec.CITY IN ('Adelaide','Brisbane','Perth') THEN 2
            -- Tier 2 - GB
            WHEN ec.COUNTRY = 'GB' AND ec.CITY IN ('Birmingham','Manchester') THEN 2
            -- Tier 3 - US
            WHEN ec.COUNTRY = 'US' AND ec.CITY IN ('Birmingham','Boise','Charleston','Fort Myers','Jackson','Kansas City','Louisville','Manchester','Memphis','New Haven','Oklahoma City','Omaha','Providence','Rancho Cucamonga','Richmond','Riverside','Sacramento','Santa Barbara','Santa Cruz','Spokane','Stamford','Tucson','Virginia Beach') THEN 3
            -- Tier 3 - CA
            WHEN ec.COUNTRY = 'CA' AND ec.CITY IN ('Halifax','Kitchener','London','Montréal','St. Catharines') THEN 3
            -- Tier 3 - AU
            WHEN ec.COUNTRY = 'AU' AND ec.CITY IN ('Gold Coast','Hobart') THEN 3
            -- Tier 3 - GB
            WHEN ec.COUNTRY = 'GB' AND ec.CITY IN ('Belfast','Edinburgh','Glasgow','Newcastle') THEN 3
            -- Default to Tier 2 if city not found
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
--    during September. Points based on GPV tier.
--    An SQL = Stage 2+ opportunity (MOVED_TO_STAGE_2_FINAL = 1)
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
    WHERE cop.SALES_TEAM = 'Sales - US Field'
      AND cop.PROGRAM_SOURCE IN ('AE Sourced', 'AE Claimed')
      AND cop.TOTAL_ANNUAL_GPV_USD >= 500000
      AND cop.MOVED_TO_STAGE_2_FINAL = 1
      AND cop.WEEK_START >= $contest_start
      AND cop.WEEK_START <= $contest_end
),

-- ============================================================
-- 3. SAMPS DEMO POINTS: +2 pts per completed SAMPS demo call
--    Tracked via SAMPS_ACTIVITIES where IS_DEMO = 1
--    Joined back to AE via OPPORTUNITY_ID -> FACT_OPPORTUNITIES_REPORTING
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
      AND sa.ACTIVITY_DATE >= $contest_start
      AND sa.ACTIVITY_DATE <= $contest_end
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
    WHERE cop.SALES_TEAM = 'Sales - US Field'
      AND cop.PROGRAM_SOURCE IN ('AE Sourced', 'AE Claimed')
      AND cop.TOTAL_ANNUAL_GPV_USD >= 500000
      AND cop.MOVED_TO_STAGE_2_FINAL = 1
      AND cop.WEEK_START >= $contest_start
      AND cop.WEEK_START <= $contest_end
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
    r.CITY,
    r.COUNTRY,
    COALESCE(s.total_sql_pts, 0) AS sql_creation_pts,
    COALESCE(d.total_demo_pts, 0) AS samps_demo_pts,
    COALESCE(t.total_target_pts, 0) AS weekly_target_pts,
    COALESCE(w.total_winner_pts, 0) AS team_winner_pts,
    (COALESCE(s.total_sql_pts, 0) + 
     COALESCE(d.total_demo_pts, 0) + 
     COALESCE(t.total_target_pts, 0) + 
     COALESCE(w.total_winner_pts, 0)) AS total_points
FROM roster r
LEFT JOIN sql_pts_agg s ON r.FULL_NAME = s.FULL_NAME
LEFT JOIN demo_pts_agg d ON r.FULL_NAME = d.FULL_NAME
LEFT JOIN target_pts_agg t ON r.FULL_NAME = t.FULL_NAME
LEFT JOIN winner_pts_agg w ON r.FULL_NAME = w.FULL_NAME
ORDER BY total_points DESC;
