select  B.SEC || '_' || D.BOOK_CODE || '_' || (case when D.book_code like 'P6%'  or D.BOOK_CODE in ('P9') then 'RESIDUAL' else D.ACCOUNT_CODE END) SEC_ACC, B.SEC 
,  (case when D.book_code like 'P6%'  or D.BOOK_CODE in ('P9') then 'RESIDUAL' else D.ACCOUNT_CODE END) ACCOUNT_CODE, D.BOOK_CODE 
, sum((case when B.PORS = 'S' then -1 else 1 END)* B.NOTIONAL) NET_NTL  
from SUMMIT.DMENV E, summit.dmbond B, 
(select trade_id, account_code, book_code, maturity_dt   
from TREASPERF.PORTFOLIO_DEFN_MV  
where asset_type_code = 'BOND' and portfolio_type_code = 'A'  
and desk_code in ('LAM', 'COLLMGT') and  (account_eff_dt is null or account_eff_dt<= :asofdate)
and                        (account_end_dt is null or account_end_dt>= :asofdate)
group by trade_id, account_code, account_end_dt, book_code, maturity_dt ) D   
where audit_current = 'Y'      and audit_entitystate in('VER','DONE')       and B.AUDIT_VERSION = E.AUDIT_VERSION       
and B.TRADEID = E.TRADEID      
and D.TRADE_ID = E.TRADEID 
and D.maturity_dt > :asofdate
and E.DMOWNERTABLE = 'BOND_TR' 
Group by B.SEC || '_' || D.ACCOUNT_CODE, SEC, ACCOUNT_CODE, BOOK_CODE  
having abs(sum((case when B.PORS = 'S' then -1 else 1 END)* B.NOTIONAL)) >0.99   
ORDER BY BOOK_CODE, ACCOUNT_CODE 
