# Timecard

The iPhone app takes its layout from a time clock and a ruled timesheet. Dates, hours and pay occupy predictable positions, so a person can compare two shifts at a glance.

## Type and ink

Barlow Condensed Bold sets the main amounts, page headings and clock button. System text handles job names, form fields and longer explanations. Monospaced labels and tabular digits keep dates and values aligned. The font and its license ship in the app and widget bundles.

`TimecardColor` defines the warm stock, ink, rules and accent colors for both iPhone appearances. A solid cobalt readout carries gross earnings. Estimated take-home uses an ink-on-stock readout with an explicit label. Vermilion marks the current day or week and the end-shift action. Job colors identify employers.

## Screen composition

- **Home** shows the amount first. The seven-day strip punches a slot for each date with completed shift hours. Its hour labels use the portion of each shift worked that day. At accessibility text sizes it becomes a list.
- **History** aligns the work date, job, clock times, hours and pay in ruled rows. The date remains attached to its row as the layout stacks.
- **Summary** prints gross and estimated take-home alongside one another. Weekly bars use a common zero baseline and show exact dollar values.
- **Settings** presents jobs as an index. Rate, pay cycle and paycheck reference belong to the job. Choice fields open a ruled list with a cobalt check on the saved value. Short choices such as pay type can be selected inline.
- **Widgets and printed summaries** share the typeface and ink colors. Print uses a fixed light palette.

`PayReadout` owns the cut corner and amount typography. `TimecardHeading` owns page titles and their rules. Routine list entries use a shared baseline or divider. Motion in a live amount follows the iPhone’s Reduce Motion setting.


## Selection controls

Use `TimecardPicker` for a saved choice and `TimecardMenu` for actions. A choice takes effect on selection. Closing or swiping down dismisses the list. Actions that open another editor run after the choice sheet closes.

`TimecardDateField` uses separate date and time buttons for a shift timestamp. The calendar heading opens month and year navigation. The clock accepts exact minutes and follows the device’s 12-hour or 24-hour format. The official payday calendar updates the editor’s draft until Save is tapped.
