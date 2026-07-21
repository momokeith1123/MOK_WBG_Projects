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
 )  select decode(trim(asset_type),'SWAPTION','SWOPT',trim(asset_type))||'_'||trim(tradeid) SECURITY_ID, nvl(parent_cust, ' ') PARENT_CUST, ' ' coll_ctry, nvl(SP_PARENT, ' ') SP, nvl(MOODY_PARENT, ' ') MOODY, nvl(FITCH_PARENT, ' ') FITCH, nvl(trade_cust, ' ') issuer_cust, nvl(country, ' ') ISSUER_CNTRY 
from  
(select asset_type, tradeid, trade_cust, parent_cust, max(moody_child) moody_child, max(sp_child) sp_child, max(fitch_child) fitch_child, max(moody_parent) moody_parent, max(sp_parent) sp_parent, max(fitch_parent) fitch_parent,  
max(IBRD_parent) IBRD_parent, max(country) country  
from (       
select de.tradeid, replace(de.audit_table, '_TR', '') asset_type, cust_info.id trade_cust, cust_info.main_parent parent_cust,   
       (case when child_dcc.NAME='SP' then child_dcc.value else null end) SP_child,  
       (case when child_dcc.NAME='MOODY' then child_dcc.value else null end) moody_child,      
       (case when child_dcc.NAME='FITCH' then child_dcc.value else null end) FITCH_child,  
       (case when parent_dcc.NAME='SP' then parent_dcc.value else null end) SP_parent,  
       (case when parent_dcc.NAME='MOODY' then parent_dcc.value else null end) moody_parent,  
       (case when parent_dcc.NAME='FITCH' then parent_dcc.value else null end) FITCH_parent,  
       (case when parent_dcc.NAME='IBRD' then parent_dcc.value else null end) IBRD_parent,         
       PARENT_DC.LOGICALCOUNTRY country         
from   
  summit.dmenv de, cust_info, 
  summit.dmcustomer child_dc,  
  summit.dmcustomer parent_dc,  
  summit.dmcust_class child_dcc,  
  summit.dmcust_class parent_dcc     
where   
  de.desk in ('LAM', 'COLLMGT','RMU') and (de.book in ('BJMA', 'P0','P1','P2','P7','P8','P9') or de.book like 'P6%' or de.book like '%LMCS' or de.book like 'P1%')   
  and (de.audit_entitystate not in ('MAT','CANC') or (DE.lastupdate >='24-sep-2015' and DE.AUDIT_ENTITYSTATE = 'MAT'))  
  and de.audit_current='Y'  
  and replace(de.audit_table, '_TR', '') not in ('BOND','DPMT') and cust_info.id=de.cust 
  and child_dc.audit_current=de.audit_current  
  and child_dc.id=cust_info.id  
  and parent_dc.audit_current=de.audit_current  
  and parent_dc.id=cust_info.main_parent    
  and CHILD_DCC.AUDIT_VERSION(+)=child_dc.audit_version  
  and CHILD_DCC.CUST(+)=CHILD_DC.ID  
  and CHILD_DCC.TYPE(+)='RISKRATE'  
  and parent_dcc.audit_version(+)=parent_dc.audit_version  
  and parent_dcc.cust(+)=parent_dc.id  
  and parent_dcc.type(+)='RISKRATE'  
) group by asset_type, tradeid, trade_cust, parent_cust)  
