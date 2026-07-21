SELECT *
FROM (
    SELECT 
        INSTRUMENT_ID,  -- Replace with the actual unique identifier for each instrument
        MNEMONIC_CODE,
        VALUE_TXT
    FROM 
        BOB.INSTRUMENT_DETAIL
    WHERE 
        MNEMONIC_CODE IN ('SECURITY_DES', 'RTG_DBRS', 'MM_MDY_RTG_SHRT') 
        AND AS_OF_DATE = :asofdate
        OR ( -- This can be achieved by checking if data exists for the specified date and, if not, defaulting to the latest available date.
            AS_OF_DATE = (
                SELECT MAX(AS_OF_DATE)
                FROM BOB.INSTRUMENT_DETAIL
                WHERE MNEMONIC_CODE IN ('SECURITY_DES', 'RTG_DBRS', 'MM_MDY_RTG_SHRT')
            )
            AND NOT EXISTS (
                SELECT 1
                FROM BOB.INSTRUMENT_DETAIL
                WHERE MNEMONIC_CODE IN ('SECURITY_DES', 'RTG_DBRS', 'MM_MDY_RTG_SHRT')
                AND AS_OF_DATE = :asofdate
            )
        )
) 
PIVOT (
    MAX(VALUE_TXT) 
    FOR MNEMONIC_CODE IN ('SECURITY_DES' AS SECURITY_DES, 
                          'RTG_DBRS' AS RTG_DBRS, 
                          'MM_MDY_RTG_SHRT' AS MM_MDY_RTG_SHRT)
);