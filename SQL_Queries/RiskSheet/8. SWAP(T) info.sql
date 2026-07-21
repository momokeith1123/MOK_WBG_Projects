select (case when A.dmownertable = 'SWAPTION' then 'SWOPT' else 'SWAP' end) ASSET_TYPE_CODE 
, (case when A.dmownertable = 'SWAPTION' then 'SWOPT' || '_' || E.TradeID else 'SWAP' || '_' || E.TradeID || '_' || A.PORS end) TradeId 
,(case when A.dmownertable = 'SWAPTION' then to_date(EXPDATE,'YYYYMMDD') else NULL end) EXPDATE  
, to_date(EFFDATE, 'YYYYMMDD') EFFDATE, to_DATE(MATDATE,'YYYYMMDD') MATDATE, (case when A.INTEREST_FIXFLOAT='FIX' then A.INTEREST_RATE else NULL end) STRIKE, 
 (case when (A.INTEREST_FIXFLOAT='FIX' and A.PORS = 'P') THEN 'RECEIVER' 
       when (A.INTEREST_FIXFLOAT='FIX' and A.PORS = 'S' ) THEN 'PAYER' 
       else NULL 
  end) PORR   
from SUMMIT.DMENV E, SUMMIT.DMASSET A, SUMMIT.DMOPTION O 
WHERE  E.Audit_Version = A.Audit_Version    
             AND    E.TradeId       = A.TradeId          
             AND    E.dmOwnerTable  = A.dmOwnerTable     
             AND    A.dmOwnerTable in ('SWAP','SWAPTION')        
             AND E.Desk ='LAM'                               
             AND E.TradeStatus in ('VER')                    
             AND E.Audit_Current ='Y'                        
             AND E.TRADEID = O.TRADEID(+) 
             AND MATDATE >= :asofdate_str
             AND A.INTEREST_FIXFLOAT='FIX' 
ORDER BY ASSET_TYPE_CODE, TradeId 
