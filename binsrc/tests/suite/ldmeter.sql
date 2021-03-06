

create table ld_metric 
(
 lm_id int  primary key,
 lm_dt datetime,
 lm_first_id int,
 lm_secs_since_start int,
 lm_n_rows bigint,
 lm_cpu int,
 lm_n_reads bigint,
 lm_read_time int,
 lm_read_pct float,
 lm_rows_per_s float,
 lm_cpu_pct float,
 lm_rusage any
 );

create index lm_dt on ld_metric (lm_dt);





-- getrusage returns:
-- 0. user cpu msec 
-- 1. sys cpu msec 
-- 2. max  resident set 
-- 3.  min flt
-- 4. maj flt
-- 5 n swap 
-- 6. blocking input
-- 7. blocking output

create procedure ld_sample (in is_first int := 0)
{
  declare ru any;
  declare now datetime;
  declare id, n_rows, read_time, last_read_time, elapsed int;
 id := sequence_next ('lm');
 now := curdatetime ();
 n_rows := (select cl_sys_stat (key_table, name_part (key_name, 2), 'touches') from sys_keys where key_name = 'DB.DBA.RDF_QUAD');
 ru := getrusage ();
  if (is_first)
    {

      insert into ld_metric (lm_id, lm_dt, lm_first_id, lm_cpu, lm_read_time, lm_n_rows, lm_rusage, lm_secs_since_start) 
	values (id, now, id, ru[0] + ru[1], sys_stat ('read_cum_time'), n_rows, ru, 0);
}
  else
    {
      declare last_dt, start_dt datetime;
      declare first_id, last_rows, last_cpu, last_read  int;
      select lm_id, lm_dt  into first_id, start_dt from ld_metric where lm_dt < now and lm_first_id = lm_id order by lm_dt desc;
      select lm_dt, lm_n_rows, lm_cpu, lm_read_time into last_dt, last_rows, last_cpu, last_read  
	from ld_metric where lm_dt < now order by lm_dt desc;

      insert into ld_metric (lm_id, lm_dt, lm_first_id, lm_cpu, lm_read_time, lm_n_rows, lm_rusage, lm_secs_since_start) 
	values (id, now, first_id, ru[0] + ru[1], sys_stat ('read_cum_time'), n_rows, ru, datediff ('second', start_dt, now));
    elapsed := datediff ('second', last_dt, now);
      update ld_metric set 
	lm_read_pct = (sys_stat ('read_cum_time') - last_read) / 10 / (0.0001 + elapsed),
	lm_cpu_pct = (((ru[0] + ru[1]) - last_cpu) / 10) / (0.001 + elapsed),
	lm_rows_per_s = (n_rows - last_rows) / (0.001 + elapsed)
	where lm_id = id;
    }
  commit work;
}


create procedure ld_meter_run (in s_delay int)
{
  declare stat, msg any;
  ld_sample (1);
  while (1)
    {
      delay (s_delay);
      stat := '00000';
      exec ('ld_sample (0)', stat, msg, null);
      if (stat <> '00000')
	{
	  rollback work;
	  log_message (stat || ' ' || msg);
	}
    }
}
