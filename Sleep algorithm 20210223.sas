*************************************************************************************************************************
*** Center for Innovative Design and Analysis
*** University of Colorado - Anschutz Medical Campus
*** Programmer: 		Laura Grau

*** Required user inputs:
		* data 				= name of input data with one week of minute by minute data
		* outdata_day 		= name of output summaries by day
		* outdata_week 		= name of output summaries by week
		* id				= patient identified
		* datetime			= date-time variable 
		* lyingdown			= binary indicator for lying down
		* sleep				= binary indicator for sleep
		* nmins				= minimum number of minutes required for a valid day
		* weekdays			= minimum number of weekdays required for a valid week
		* weekenddays		= minimum number of weekend days required for a valid week
************************************************************************************************************************;


%macro sleep  (data,outdata_day, outdata_week, id, datetime, lyingdown, sleep, nmins, weekdays, weekenddays)  ;

/***************************************************************************************************
part one. define clock times of bedtime, sleep onset, sleep offset, and waketime
***************************************************************************************************/
***********************************************************************************
1. read in data, create definition of night (7:00 PM-11:59 AM), create date_sleep variable,
correct incorrect sleep variable
**********************************************************************************;

data validdata;
set &data ;

if hour(timepart(&datetime)) >= 19 or hour(timepart(&datetime)) < 12 then interval='night';
else interval = 'day';

if hour(timepart(&datetime)) < 12 then date_sleep=(datepart(&datetime)-1);
else date_sleep=datepart(&datetime);
format date_sleep mmddyy10.;

if &lyingdown=0 and &sleep=1 then &sleep=0;
minute=1;
run;

proc sort data=validdata;by &id date_sleep;run;

***********************************************************************************
2. validity criteria for a valid day
***********************************************************************************;
proc sql;
create table valid_cohort as
select *, sum(minute) as sum_minutes
from validdata
group by &id, date_sleep;
quit;

data valid_cohort;
set valid_cohort;
dif24=1440-sum_minutes;
run;

data cohort invalid;
set valid_cohort;
if sum_minutes>=&nmins then output cohort;
else output invalid;
run;

proc sort data=cohort; by &id &datetime;run;

***********************************************************************************
exploratory: sum total &sleep and &sleep during the day and &sleep during the night.
        these are raw estimations.
***********************************************************************************;
		*crude total &sleep per day;
        proc sql;
        create table total_sleep as
        select &id, date_sleep, sum(&sleep) as total_sleep, sum(&lyingdown) as total_lyingdown
        from cohort
        group by &id,date_sleep
        order by &id,date_sleep;
        quit;
		*crude daytime &sleep;
        proc sql;
        create table day_sleep as
        select &id, date_sleep, sum(&sleep) as daytime_sleep, sum(&lyingdown) as daytime_lyingdown
        from cohort
        where interval= 'day'
        group by &id,date_sleep
        order by &id,date_sleep;
        quit;
		*crude night &sleep;
        proc sql;
        create table night_sleep as
        select &id, date_sleep, sum(&sleep) as night_sleep, sum(&lyingdown) as night_lyingdown
        from cohort
        where interval= 'night'
        group by &id,date_sleep
        order by &id, date_sleep;
        quit;

		*these are the crude &sleep variables;
        proc sql;
        create table cohort_1 as
        select a.*, b.daytime_sleep, b.daytime_lyingdown, c.night_sleep, c.night_lyingdown, d.total_sleep, d.total_lyingdown

        from cohort a left join day_sleep b
        on a.&id=b.&id and a.date_sleep=b.date_sleep

        left join night_sleep c
        on a.&id=c.&id and a.date_sleep=c.date_sleep

        left join total_sleep d
        on a.&id=d.&id and a.date_sleep=d.date_sleep;
        quit;
 
***********************************************************************************
3. create crude bedtime, sleep onset, sleep offset, and waketime variables
***********************************************************************************;
proc sql;
create table sleep_var as
select &id,date_sleep, max(&datetime) as SE_1 format datetime16., min(&datetime) as SO_1 format datetime16.
from cohort_1
where interval= 'night' and &sleep=1
group by &id,date_sleep
order by &id;
quit;

proc sql;
create table lyingdown_var as
select &id,date_sleep, max(&datetime) as WT_1 format datetime16., min(&datetime) as BT1 format datetime16.
from cohort_1
where interval= 'night' and &lyingdown=1
group by &id,date_sleep
order by &id;
quit;



***********************************************************************************
4. merge all together
***********************************************************************************;
proc sql;
create table fulldata as
select a.*, b.SE_1, b.SO_1, c.WT_1, c.BT1

from cohort_1 a left join sleep_var b
on a.&id=b.&id and a.date_sleep=b.date_sleep

left join lyingdown_var c
on a.&id=c.&id and a.date_sleep=c.date_sleep;
quit;

proc sort data=fulldata; by &id &datetime;run;








/****************************************************************************************
*****************************************************************************************
****************************************************************************************/

***********************************************************************************
5.  correcting the SLEEP ONSET  variable
***********************************************************************************;


*********************************************
5.1.        limit to observations currently used to define nighttime &sleep
*********************************************;
data weirdsleep;
set fulldata;
if &datetime>=SO_1 and &datetime<=SE_1;
run;

proc sort data=weirdsleep;
by &id &datetime date_sleep ;run;

*********************************************
5.2.        mark changes in &sleep/lying down

mark = goes from lying down 1 to 0 (get up)
mark_1 = goes from lying down 0 to 1 (lie down)

wu = goes from &sleep  1 to 0 (wake up)
fa = goes from &sleep 0 to 1 (fall asleep)
*********************************************;

data weirdsleep1;
set weirdsleep;
by &id date_sleep notsorted;
retain mark mark_1 wu fa;

*set first observation per person per day as missing;
if first.date_sleep then mark=.;
if first.date_sleep then mark_1=.;
if first.date_sleep then wu=.;
if first.date_sleep then fa=.;

if dif(&lyingdown)=-1 then mark=&datetime; 
if &lyingdown=1 and lag(&lyingdown)=0 then mark_1=&datetime;

if dif(&sleep)=-1 then wu=&datetime;
if &sleep=1 and lag(&sleep)=0 then fa=&datetime;
format wu datetime16. fa datetime16. mark datetime16. mark_1 datetime16.  SE_1 datetime16. SO_1 datetime16. WT_1 datetime16. BT1 datetime16.;run;


*********************************************
5.3.        limit to observations before midnight
*********************************************;

data weirdsleep2;
set weirdsleep1;
*calculate time elapsed between falling asleep and waking up...
calculate time elapsed between lying down and getting up...;
difference_sleep=fa-wu;
difference_ld=mark_1-mark;
where timepart(&datetime)<='23:59:00't & timepart(&datetime)>='19:00:00't;
run;

proc sql;
create table weirdsleep3 as
select *, max(difference_ld) as maxdiff
from weirdsleep2
group by &id, date_sleep order by &id, &datetime;quit;

*create dataset with only obs with more than 10 minutes of not lying down or sleeping;
data weirdsleep4;
set weirdsleep3;
if maxdiff>=600 and difference_sleep>=600 then ind=1;run;

*create dataset with only obs with more than 10 minutes of not lying down or sleeping;
data weirdsleep5;
set weirdsleep4;
if ind=1;
run;

*SO_2 becomes version two of SO_1;
proc sql;
create table weirdsleep6 as
select &id, date_sleep, min(&datetime) as SO_2 
from weirdsleep5
group by &id, date_sleep
order by &id;
quit;


*fulldata2 is the full dataset with two versions of falling asleep;
proc sql;
create table fulldata2 as
select a.*, b.SO_2 format datetime16.
from fulldata a
left join weirdsleep6 b
on a.&id=b.&id and a.date_sleep=b.date_sleep
order by &id, &datetime;
quit;




*********************************************
5.4.        for people who are not sleeping at midnight
*********************************************;
data weirdsleep7;
set fulldata2;
if timepart(&datetime)='0:00:00't and &sleep=0 then midnight_nosleep=1;
if timepart(&datetime)='0:00:00't then midnight_date=&datetime;
format SE_1 datetime16. SO_1 datetime16. WT_1 datetime16. BT1 datetime16.;
run;

proc sql;
create table weirdsleep8 as
select *, max(midnight_nosleep) as md_ns, max(midnight_date) as md_date
from weirdsleep7
group by &id, date_sleep
order by &id, &datetime;
quit;

*pull out people who are not sleeping at midnight and their SO_1 is before midnight;
data weirdsleep9;
set weirdsleep8;
if md_ns=1 and interval='night' and (SO_1<md_date or SO_2<md_date);
format md_date datetime16.;
run;

data weirdsleep10;
set weirdsleep9;
by &id date_sleep notsorted;
retain mark mark_1 wu fa;

*set first observation per person per day as missing;
if first.date_sleep then mark=.;
if first.date_sleep then mark_1=.;
if first.date_sleep then wu=.;
if first.date_sleep then fa=.;

if dif(&lyingdown)=-1 then mark=&datetime;
if &lyingdown=1 and lag(&lyingdown)=0 then mark_1=&datetime;

if dif(&sleep)=-1 then wu=&datetime;
if &sleep=1 and lag(&sleep)=0 then fa=&datetime;
run;

data weirdsleep11;
set weirdsleep10;
if &datetime<md_date;run;

*capture the last time the person woke up before midnight;
proc sql;
create table weirdsleep12 as
select &id, date_sleep, max(wu) as last_wu format datetime16., max(fa) as last_fa format datetime16. , max(mark_1) as last_ld format datetime16., max(mark) as last_gu format datetime16.
from weirdsleep11 where interval='night'
group by &id, date_sleep;
quit;

proc sql;
create table weirdsleep13 as
select a.*, b.last_wu, b.last_fa, b.last_ld, b.last_gu
from weirdsleep8 a left join weirdsleep12 b
on a.&id=b.&id and a.date_sleep=b.date_sleep
order by &id, &datetime;
quit;

data weirdsleep13;
set weirdsleep13;
if (last_fa<last_wu) and (last_ld<last_gu) then do;
diff1=md_date-last_wu;
diff2=md_date-last_gu;
end;
format last_wu datetime16.;
run;

*10 minutes of no lying down or sleeping;
data weirdsleep13;
set weirdsleep13;
if diff1>600 and diff2>600 then use_data=1;
run;


*if use then merge to full data and select the first &sleep after midnight;
proc sql;
create table weirdsleep14 as
select &id, date_sleep, max(use_data) as use
from weirdsleep13
group by &id, date_sleep
order by &id;
quit;

proc sql;
create table weirdsleep15 as
select a.*, b.use
from weirdsleep8 a left join weirdsleep14 b
on a.&id=b.&id and a.date_sleep=b.date_sleep;
quit;

proc sql;
create table weirdsleep16 as
select &id, date_sleep, min(&datetime) as SO_3 format datetime16.
from weirdsleep15 where use=1 and &datetime>md_date and interval='night' and &sleep=1
group by &id, date_sleep
order by &id, date_sleep;
quit;


*fulldata3 is the full dataset with two versions of falling asleep;
proc sql;
create table fulldata3 as
select a.*, b.SO_3
from fulldata2  a
left join weirdsleep16 b
on a.&id=b.&id and a.date_sleep=b.date_sleep
order by &id, &datetime;
quit;


data fulldata3;
set fulldata3;
if SO_3 ne . then sleep_onset=SO_3;
else if SO_2 ne . then sleep_onset=SO_2;
else sleep_onset=SO_1;
format sleep_onset datetime16.;
run;

***********************************************************************************
6.  correcting the BT1 variable
***********************************************************************************;

*********************************************
6.1.        bring in full data from previous step. create new vars.
mark = goes from lying down 1 to 0 (get up)
mark_1 = goes from lying down 0 to 1 (lie down)

limit dataset time between first lying down and first fall asleep
*********************************************;
data ld_1;
set fulldata3(keep=&id &datetime date_sleep &lyingdown &sleep sleep_onset BT1);
if dif(&lyingdown)=-1 then mark=&datetime;
if &lyingdown=1 and lag(&lyingdown)=0 then mark_1=&datetime;
run;

data ld_1;
set ld_1;
if &datetime>=BT1 and &datetime<=sleep_onset;
run;

* select the last time the person laid down before falling asleep*;
proc sql;
create table ld_2 as
select &id, date_sleep, max(mark_1) as bedtime1
from ld_1
group by &id,date_sleep
order by &id;
quit;

*merge to full data*;
proc sql;
create table ld_3 as
select a.*, b.bedtime1
from fulldata3 a
left join ld_2 b
on a.&id=b.&id and a.date_sleep=b.date_sleep
order by &id, &datetime;
quit;

*bedtime is our final &lyingdown varibale;
data ld_3;
set ld_3;
if bedtime1=. then bedtime=bt1;
else bedtime=bedtime1;
format sleep_onset datetime16. 
bedtime datetime16.  ;
run;

proc sort data=ld_3; by &id date_sleep &datetime;run;

* there are some people with no &sleep for that day! these are most likely people who took the armband off that day*;
proc sql;
create table ld_4 as
select *,sum(&lyingdown) as tib1, sum(&sleep) as tst1
from ld_3
group by &id, date_sleep
order by &id, &datetime;
quit;


data fulldata4;set ld_4;
if tib1=0 and tst1=0 then delete;
drop tib1 tst1 ; run;



***********************************************************************************
6.5.   edit SE_1 and WT_1
***********************************************************************************;
data test65;
set fulldata4;
by &id date_sleep notsorted;
where timepart(&datetime)>='0:00:00't and timepart(&datetime)<='11:59:00't and interval='night' and &datetime>=bedtime;
if &lyingdown=0 and &sleep=0 then delete;
if first.&id and first.date_sleep then test=.;
test=round(dif(&datetime),1);
if test <5400 then test=.;
if first.date_sleep then test=.;
test_date=lag(&datetime);
run;


data test65_a;
set test65;
if test ne . and lag(date_sleep)=date_sleep then true_gu=test_date;
format true_gu datetime16. test_date datetime16.;run;

proc sql;
create table test65_b as
select *, min(true_gu) as true_gu1 format datetime16.
from test65_a
group by &id,date_sleep order by &id,&datetime;
quit;

data test65_c;
set test65_b;
if true_gu1=. then delete;
if &datetime>=true_gu1 then delete;run;

proc sql;
create table test65_d as
select &id, date_sleep, max(&datetime) as WT_2 format datetime16.
from test65_c
group by &id, date_sleep;
quit;

proc sql;
create table test65_full as
select a.*,b.WT_2
from fulldata4 a left join test65_d b
on a.&id=b.&id and a.date_sleep=b.date_sleep
order by &id,&datetime;quit;

data test65_done;
set test65_full;
if WT_2 ne . then waketime=WT_2;
else waketime=WT_1; format waketime datetime16.;
run;

data test_gu;
set test65_done;
where WT_2 ne . and &sleep=1 and &datetime<=WT_2;
run;

proc sql;
create table test_gu1 as
select &id, date_sleep, max(&datetime) as SE_2 format datetime16.
from test_gu 
group by &id, date_sleep;
quit;

proc sql;
create table test_gu2 as
select a.*,b.SE_2
from test65_done a left join test_gu1 b
on a.&id=b.&id and a.date_sleep=b.date_sleep
order by &id, &datetime;
quit;

data fulldata5;
set test_gu2;
if SE_2 ne . then sleep_offset=SE_2;
else sleep_offset=SE_1;
format sleep_offset datetime16.;
run;

/***************************************************************************************************
PART TWO: Now that we have clock time variables, we can create the SLEEP varibles
***************************************************************************************************/
***********************************************************************************
1. Limit to time between bedtime and waketime --Add minutes of lying down for TIB
***********************************************************************************;
data lying_sum;
set fulldata5;
by &id;
if bedtime<= &datetime <=waketime;
run;

proc sql;
create table lying_sum1 as
select &id,date_sleep,sum(&lyingdown) as tib
from lying_sum
group by &id, date_sleep
order by &id;
quit;

***********************************************************************************
2. Limit to time between sleep onset and offeset --Add minutes of lying down for TST
***********************************************************************************;
data sleep_sum;
set fulldata5;
by &id;
if sleep_onset<=&datetime<=sleep_offset;
run;

proc sql;
create table sleep_sum1 as
select &id,date_sleep,sum(&sleep) as tst
from sleep_sum
group by &id, date_sleep
order by &id;
quit;


***********************************************************************************
3. Merge full data & sort
***********************************************************************************;
proc sql;
create table two_3 as
select a.*, b.tib, c.tst
from fulldata5 a

left join lying_sum1 b
on a.&id=b.&id and a.date_sleep=b.date_sleep

left join sleep_sum1 c
on a.&id=c.&id and a.date_sleep=c.date_sleep;
quit;


proc sort data=step6;
by &id &datetime;
run;


***********************************************************************************
4. limit dataset to the observations between falling asleep at first and last waking up
create wake variable (inverse of &sleep)
***********************************************************************************;

data two_4;
set two_3;
if &sleep=0 then awake=1;
else if &sleep=1 then awake=0;

if dif(&sleep)=-1 then wu=1;

if sleep_onset<= &datetime <=sleep_offset;
run;



***********************************************************************************
5. Sleep fragmentations and WASO
***********************************************************************************;

data two_5;
set two_4;
by &id date_sleep notsorted;
retain sf_time;
/*reset with each new night*/
if  first.date_sleep then sf_time=.;
retain sf_time;
/*everytime the person is awake, we are getting a new time.
this allows us to pick the next occurence of wakefulness 10 mins after the last time they fell asleep*/
if awake=1 then sf_time=&datetime;
dif=sf_time-lag(sf_time);
run;

/*at least 10 minutes have passed since the last time the person was awake/fell asleep*/
data two_5_1;
set two_5;
by &id date_sleep notsorted;
if dif>=600 then count_10min=1;
if dif>=120 then count_2min=1;
if dif>=180 then count_3min=1;
if dif>=240 then count_4min=1;
if dif>=300 then count_5min=1;
run;

/*count amount of time awake after &sleep onset and &sleep fluctuations*/
proc sql;
create table two_5_2 as
select &id,date_sleep,sum(awake) as waso, sum(wu) as sf_rawsum, sum(count_10min) as sf_10,
sum(count_2min) as sf_2, sum(count_3min) as sf_3, sum(count_4min) as sf_4, sum(count_5min) as sf_5
from two_5_1
group by &id, date_sleep;
quit;

/*adding 1 to previous count because we are not capturing the first fluctuation given current code*/
data two_5_2;
set two_5_2;
sf_raw=sf_rawsum+1;
sf_10min=sf_10+1;
sf_2min=sf_2+1;
sf_3min=sf_3+1;
sf_4min=sf_4+1;
sf_5min=sf_5+1;
run;

proc sort data=two_5_2;
by &id date_sleep;
run;


***********************************************************************************
6. Merge to full dataset
***********************************************************************************;
        proc sql;
        create table two_6 as
        select a.*, b.waso,b.sf_raw, b.sf_10min, b.sf_2min, b.sf_3min, b.sf_4min, b.sf_5min
        from two_3 a left join two_5_2 b
        on a.&id=b.&id and a.date_sleep=b.date_sleep
        order by &id;
        quit;
        proc sort data=two_6;
        by &id &datetime;
        run;


***********************************************************************************
7. SOL
***********************************************************************************;


data two_7 (drop=dis_dt);
set two_6;
by &id;
format dis_dt datetime20.;
retain dummy dis_dt;

if &datetime>=bedtime then do;

if first.&id then do;
dummy=0;
dis_dt=constant('bigint');
end;

if &lyingdown=1 then dummy=1;

if bedtime<=&datetime then do;
if dif(&sleep)=1 then dis_dt=&datetime;
if &datetime>dis_dt+'00:10:00't then dummy=0;
end; end;
run;

data two_7_1;
set two_7;
if (dummy-lag(dummy)=-1) then sol_date=&datetime;
format sol_date datetime16.;
run;

data two_7_1;set two_7_1;
dummy2=0;
if &datetime>=bedtime then do;
if sleep_onset=bedtime then do;
if &datetime<=sleep_onset+'00:10:00't and &sleep=1 then dummy2=1; *changed this to 10;
end;
end;
run;


proc sql;
create table two_7_2 as
select &id,date_sleep,min(sol_date) as sol_date format datetime16.
from two_7_1
group by &id, date_sleep;
quit;

***********************************************************************************
8. Merge to full dataset
***********************************************************************************;
proc sql;
create table two_8 as
select a.*, b.sol_date
from two_6 a left join two_7_2 b
on a.&id=b.&id and a.date_sleep=b.date_sleep
order by &id;
quit;

proc sort data=two_8;
by &id &datetime;
run;

*limit final datasets*;
data two_8_1;
set two_8;
h_waketime=timepart(waketime)/3600;
h_sleep_offset=timepart(sleep_offset)/3600;
h_sol=timepart(sol_date)/3600;
h_bedtime=timepart(bedtime)/3600;
h_sleep_onset=timepart(sleep_onset)/3600;
if h_sleep_onset <6 then do;
duration=h_sleep_offset-h_sleep_onset;
end;
else do;
duration=h_sleep_offset+(24-h_sleep_onset);
end;

midpoint=h_sleep_onset+(duration/2);
if midpoint>24 then midpoint=midpoint-24;
run;

data two_8_1;
set two_8_1;
sol=round(((h_sol-h_bedtime)*60)-1,1) ;
format sol z8.5;
run;

data final1;
set two_8_1;
fwt=(h_waketime-h_sleep_offset)*60;
if sol<0 then do;
sol=((24.00-h_bedtime)+h_sol)*60;
end;
if h_bedtime=h_sol then sol=10;
run;


/***************************************************************************************************
PART THREE. Create output datasets
***************************************************************************************************/
proc sql;
create table final_byday as
select &id,date_sleep,max(tib) as tib, max(fwt) as fwt, max(tst) as tst, max(waso) as waso,
max(sf_raw) as sf_raw, max(sf_10min) as sf_10min, max(sf_2min) as sf_2min, max(sf_3min) as sf_3min,
max(sf_4min) as sf_4min, max(sf_5min) as sf_5min, max(sol) as sol, max(daytime_sleep) as total_daytime_sleep,
max(total_sleep) as total_sleep, max(total_lyingdown) as total_lyingdown,
max(daytime_lyingdown) as total_daytime_lyingdown, max(sleep_onset) as sleep_onset, max(waketime) as WT_1, 
max(sleep_offset) as SE_1, max(bedtime) as bedtime, max(h_sleep_onset) as h_sleep_onset, max(h_bedtime) as h_ld, 
max(h_waketime) as h_waketime,max(h_sleep_offset) as h_sleep_offset, max(midpoint) as h_midpoint, max(duration) as duration
from final1
group by &id, date_sleep;
quit;

data final_byday;
set final_byday;
se=tst/tib;
p_nightsleep=tst/total_sleep;
p_nightlying=tib/total_lyingdown;
if tst<420 then tst_cat=1;
else if 420<=tst<=540 then tst_cat=2;
else if tst>540 then tst_cat=3;

/*valid data by day*/
day=weekday(date_sleep);
if day in(1,7) then weekend=1;
else if day in(2,3,4,5,6) then weekday=1;
run;


***********kick out shift workers********************;
title 'people getting kicked out for shift work';
proc print data=final_byday;
where p_nightsleep<0.6;
var &id date_sleep p_nightsleep;run;
title;


data &outdata_day shift;
set final_byday;
if sf_raw=. then sf_raw=0;
if p_nightsleep<0.6 then output shift;
else output &outdata_day;
run;


proc sql;
create table finaldata as
select &id,count(unique date_sleep) as count
from final_byday
group by &id;
quit;

proc sql;
create table finalsum as
select sum(count) from finaldata;quit;


data times;
set &outdata_day;
if h_sleep_onset<12 then h_sleep_onset=h_sleep_onset+24;
if h_ld<12 then h_ld=h_ld +24;
run;

/* create summary by week*/
proc sql;
create table final_byweek as
select &id,count(unique date_sleep) as valid_days,sum(weekend) as validweekends, sum(weekday) as validweekdays, 
mean(se) as se,mean(tib) as tib, mean(fwt) as fwt, mean(tst) as tst, mean(waso) as waso, mean(sf_raw) as sf_raw, 
mean(sf_10min) as sf_10min, mean(sf_2min) as sf_2min, mean(sf_3min) as sf_3min,
mean(sf_4min) as sf_4min, mean(sf_5min) as sf_5min, mean(sol) as sol, 
mean(total_daytime_sleep) as total_daytime_sleep, mean(total_daytime_lyingdown) as total_daytime_lyingdown,
mean(total_sleep) as total_sleep, mean(h_sleep_onset) as h_sleep_onset, mean(h_ld) as h_ld, mean(h_waketime) as h_waketime,mean(h_sleep_offset) as h_sleep_offset, 
std(h_waketime) as regularity, mean(h_midpoint) as h_midpoint, mean(duration) as avg_duration
from times
group by &id;
quit;


/*limit to valid data-- */

data &outdata_week;
set final_byweek;
if validweekends>= &weekenddays and validweekdays>= &weekdays;
run;

proc datasets lib=work nolist kill;quit;run;
%mend;


