WITH 
Table1 AS (
    SELECT secid, identifiertype, UPPER(REGEXP_REPLACE(identifier, '\s+', ' ')) AS identifier
    FROM SUMMIT.DMSECIDNT b
    WHERE IDENTIFIERTYPE = 'OTH'
    AND audit_version = (
        SELECT MAX(a.audit_version)
        FROM SUMMIT.DMSECIDNT a
        WHERE a.secid = b.secid
    )
),
Table2 AS (
   select sec, remarks1 as "Manual Schedule?"
   from summit.dmsec 
   where audit_current = 'Y' and remarks1 = 'MANUAL'
),

Table3 AS (
    SELECT secid, 
       TRIM(REPLACE(identifier, 'MTG_PREPAY_SPEED=', '')) AS "PPSPD",
       TRIM(SUBSTR(TRIM(REPLACE(identifier, 'MTG_PREPAY_SPEED=', '')), 1, LENGTH(TRIM(REPLACE(identifier, 'MTG_PREPAY_SPEED=', ''))) - INSTR(REVERSE(TRIM(REPLACE(identifier, 'MTG_PREPAY_SPEED=', ''))), ' '))) AS "Prepay Speed",
       TRIM(SUBSTR(TRIM(REPLACE(identifier, 'MTG_PREPAY_SPEED=', '')), LENGTH(TRIM(REPLACE(identifier, 'MTG_PREPAY_SPEED=', ''))) - INSTR(REVERSE(TRIM(REPLACE(identifier, 'MTG_PREPAY_SPEED=', ''))), ' ') + 1)) AS "Prepay Unit",
       CASE 
           WHEN identifier IS NOT NULL THEN 'Y'
           ELSE ''
     END AS "Specified SPD?"
    FROM SUMMIT.DMSECIDNT b
    WHERE IDENTIFIERTYPE = 'PPSPD'
    AND audit_version = (
        SELECT MAX(a.audit_version)
        FROM SUMMIT.DMSECIDNT a
        WHERE a.secid = b.secid
)
),
Table4 AS (
    SELECT secid, TRIM(REPLACE(identifier, 'YLD_FLAG=', '')) AS "Yield Flag",
     CASE 
           WHEN identifier IS NOT NULL THEN 'Y'
           ELSE ''
     END AS "Specified YLD FLAG?"
    FROM SUMMIT.DMSECIDNT b
    WHERE IDENTIFIERTYPE = 'YDFLG'
    AND audit_version = (
        SELECT MAX(a.audit_version)
        FROM SUMMIT.DMSECIDNT a
        WHERE a.secid = b.secid
    )
),
Table5 AS (
    SELECT 
        PPSPEED AS "BB Default PPSPD", 
        UPPER(ID) AS ID_UPPER,
        CASE 
            WHEN PPSPEED = 'N.A.' THEN PPSPEED
            ELSE TRIM(REGEXP_SUBSTR(PPSPEED, '^[0-9]+(\.[0-9]+)?')) 
        END AS "BB Default Speed",
        CASE 
            WHEN PPSPEED = 'N.A.' THEN PPSPEED
            ELSE TRIM(REGEXP_REPLACE(PPSPEED, '^[0-9]+(\.[0-9]+)?', ''))
        END AS "BB Speed Unit"
    FROM DATAREP.SDR_MBS_PREPAYMENT c
    WHERE ASOFDATE = :asofDate
)
SELECT Table1.secid, Table1.identifiertype, Table1.identifier, 
       Table2."Manual Schedule?", 
       Table3."PPSPD", Table3."Prepay Speed",Table3."Prepay Unit", Table4."Yield Flag", 
       Table3."Specified SPD?", Table4."Specified YLD FLAG?",
       Table5."BB Default PPSPD", Table5."BB Default Speed", Table5."BB Speed Unit"
FROM Table1
LEFT JOIN Table2 ON Table1.secid = Table2.sec
LEFT JOIN Table3 ON Table1.secid = Table3.secid
LEFT JOIN Table4 ON Table1.secid = Table4.secid
LEFT JOIN Table5 ON Table1.IDENTIFIER = Table5.ID_UPPER
WHERE Table2."Manual Schedule?" IS NOT NULL
   OR Table3."PPSPD" IS NOT NULL
   OR Table4."Yield Flag" IS NOT NULL
   OR Table5."BB Default PPSPD" IS NOT NULL;