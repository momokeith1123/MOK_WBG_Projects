ALTER SESSION SET CURRENT_SCHEMA = TREASPERF;


SELECT *
FROM  all_tab_columns
where owner = 'TREASPERF'
ORDER BY table_name ; 


select * 
from TREASPERF.benchmark_return 
where as_of_date = to_date('20/07/2026', 'DD/MM/YYYY')
order by book_currency_code ;

select *
from CURR_TRADE_PERF_V
where as_of_date = to_date('20/07/2026', 'DD/MM/YYYY');

select *
from PORTFOLIO_HOLDING
where as_of_date = to_date('20/07/2026', 'DD/MM/YYYY')
order by book_code;

SELECT owner, table_name, column_name
FROM all_tab_columns
    WHERE UPPER(column_name) = 'HOLDING_VALUE_AMT'
    ORDER BY owner, table_name;