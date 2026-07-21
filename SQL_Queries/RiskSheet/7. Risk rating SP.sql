with 
 dmc 
 as 
 ( 
 select id, replace(parent, ' ', null) as parent 
 from  
  summit.dmcustomer 
 where audit_Current='Y'  
 ), 
 cust_hier 
 as 
 ( 
     select id, parent, level level_nbr, connect_by_root id main_parent, SYS_CONNECT_BY_PATH(parent, '/') hier 
     from  
     dmc  
     connect by prior id=parent 
 ), 
 max_lvl_inf 
 as 
 (select id, max(level_nbr) max_lvl 
  from cust_hier 
  group by id 
 ), 
 cust_info 
 as  
 ( 
     select cust_hier.* 
     from cust_hier, max_lvl_inf 
     where  
       cust_hier.id=max_lvl_inf.id 
       and cust_hier.level_nbr=max_lvl_inf.max_lvl 
 )  (select security_id, nvl(max(parent_cust), ' ') parent_cust, nvl(max(coll_ctry), ' ') coll_ctry, nvl(max(sp), ' ') sp, nvl(max(moody), ' ') moody, nvl(max(fitch), ' ') fitch, nvl(max(ISSUER),' ') issuer_cust, nvl(max(country), ' ') ISSUER_CNTRY 
from(  
select DS.SEC, trim(ds.type)||'_'||trim(ds.ccy)||'_'||ds.sec security_id,   
       cust_info.main_parent parent_cust, ds.issuer,  
       (case when DSC.NAME='COLL_CTR' then dsc.classvalue else null end) coll_ctry,  
       (case when DSC.NAME='MOODY' then dsc.classvalue else null end) moody,  
       (case when DSC.NAME='SP' then dsc.classvalue else null end) SP,  
       (case when DSC.NAME='FITCH' then dsc.classvalue else null end) FITCH,  
       (case when DSC.NAME='IBRD' then dsc.classvalue else null end) IBRD,  
       DS.COUNTRY 
from   
    summit.dmsec ds,   
    SUMMIT.DMSECCLASS dsc,  
(  
     select distinct db.sec   
    from   
        summit.dmbond db,  
        summit.dmenv de  
    where   
     db.tradeid=de.tradeid  
     and db.audit_version=de.audit_version  
     and de.audit_current='Y'  
     and de.desk in ('COLLMGT', 'LAM') and (de.book in ('BJMA', 'P0','P1','P2','P7','P8','P9') or de.book like 'P6%')  
) sec_info, cust_info           
where  ds.sec=sec_info.sec and ds.audit_current='Y'  and cust_info.id=ds.ISSUER  
    and dsc.secid(+)=DS.SEC  
    and DSC.AUDIT_VERSION(+)=DS.AUDIT_VERSION  
    and DSC.CLASSTYPE(+)='RISKRATE'  
 union 
 select DS.SEC, trim(ds.type)||'_'||trim(ds.ccy)||'_'||ds.sec security_id,  
        cust_info.main_parent parent_cust,  ds.issuer , 
        (case when DSC.NAME='COLL_CTR' then dsc.classvalue else null end) coll_ctry, 
        (case when DSC.NAME='MOODY' then dsc.classvalue else null end) moody, 
        (case when DSC.NAME='SP' then dsc.classvalue else null end) SP, 
        (case when DSC.NAME='FITCH' then dsc.classvalue else null end) FITCH, 
        (case when DSC.NAME='IBRD' then dsc.classvalue else null end) IBRD, 
       DS.COUNTRY 
 from 
     summit.dmsec ds,
     SUMMIT.DMSECCLASS dsc,
 (
      select distinct db.sec
     from
         summit.dmbond db,
         summit.dmenv de
     where
      Db.tradeid = de.tradeid
      and db.audit_version=de.audit_version
      and de.audit_current='Y'
      and de.desk in ('COLLMGT', 'LAM') and (de.book in ('BJMA', 'P0','P1','P2','P7','P8','P9') or de.book like 'P6%')
 ) sec_info, cust_info
 where
         DS.Sec = sec_info.Sec
     and ds.audit_current='Y' and cust_info.id=ds.ISSUER 
     and dsc.secid(+)=DS.SEC
     and DSC.AUDIT_VERSION(+)=DS.AUDIT_VERSION
     and DSC.CLASSTYPE(+)='LCTRYGRP'
) group by sec, security_id    )  
