# Salary mode

Choose **Salary** during onboarding, or open **Settings → your job → Set up salary mode**.
Enter an annual gross salary or a gross amount per paycheck, the pay frequency,
a known first day of a pay cycle, and the date salary should start counting.
Payday is separate from the cycle boundary; it can fall up to 30 days before
or 60 days after a period ends.

## Earnings visualization

- **Continuous** spreads a paycheck over the full pay period, including weekends.
- **Selected workdays** spreads the same paycheck over chosen weekdays. An
  optional daytime work window controls when the counter moves. Paid holidays
  and vacation remain part of those selected days.
- First and last partial periods are prorated. Complete periods always retain
  their fixed paycheck amount, irrespective of the visualization choice.
- Annual amounts use 52 weekly, 26 biweekly, 24 semimonthly, or 12 monthly checks.
  Employers using another annualization convention can use the per-paycheck input.
- Dates and work windows use the agreement's saved time zone. Monthly anchors,
  unequal semimonthly periods, and daylight saving changes use calendar boundaries.

Home shows a live salary counter, pay-period progress, today's accrued amount,
month/year gross totals, and the next expected payday. Gross and estimated
take-home follow the existing display preference and tax settings. The counter
is a visualization estimate, separate from cash received.

Salary participates in shared summaries, weekly charts, pay-period archives,
PDF exports, and widgets. App counters update while Home is visible; widgets
use five-minute timeline entries, subject to the system's refresh policy.
Earnings are derived from saved agreements and the current date, so reopening
the app does not require a timer to have run in the background. Widget reads
and future snapshots do not create shifts, paychecks, or work logs.

## Paychecks and work hours

Open **Paychecks, hours & salary history** from Home, or **Salary, paychecks &
work hours** from History. Each period supports an actual received paycheck
with gross, optional take-home, received date, and notes. A paycheck can be
edited or removed. Overlapping duplicate paycheck records are rejected.
Recording or removing a deposit does not add to or subtract from accrued salary.

Work hours are optional daily entries. Their effective rate divides accrued
salary by logged hours; they never change salary earnings. Entries can be
edited or removed, with a maximum of 24 hours per agreement-local day. Hourly
shift controls reject salary jobs to prevent counting the same income twice.

## Changes and history

Salary agreements are effective dated. Later revisions start at pay-period
boundaries today or later and retain earlier amounts, cycles, and visualization
settings. Schedule a change in job settings; the editor suggests the next
period boundary. When changing frequency or cycle anchor, choose a shared
boundary of the old and new cycles. The latest upcoming change can be canceled.

Switching to hourly pay stops salary accrual at that moment and keeps salary
history, paycheck records, and hours. Archiving a job also stops its salary;
historical salary remains in all-time totals. Converting an hourly job requires
ending its active shift and choosing a salary start after its completed work.
Upcoming hourly schedules and templates for that job are removed on conversion.

Existing jobs default to hourly after migration. The regression suite includes
a synthetic SQLite store created with the released pre-salary schema, validating
preserved hourly history and persistence of the new salary records.
