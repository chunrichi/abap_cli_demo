---
name: abap-style
description: Structured process for applying repository-specific ABAP style. Use BEFORE editing or generating ABAP code — reports, classes, function modules, enhancements, or full processes. Guides following the project's specific development conventions.
metadata:
  version: "1.0.7"
---

## ABAP Style

Apply this skill when changing ABAP in this repo. The goal is consistency with the existing personal style across the current project structure, not generic "best practice" rewrites.

### Core Intent

- Keep business logic unchanged unless the user explicitly asks for logic changes.
- Prefer code that is easy to scan in this workspace and easy to hand over.
- Reduce unnecessary abstraction. Do not introduce helper classes, frameworks, or layers unless they clearly solve a real problem already present in the repo.
- Match the local style of the program being edited before applying cross-project cleanup.

### Project Patterns

The current project shows a few recurring program families:

- Small wrapper reports can be extremely thin. A report may contain only one top-level `PERFORM`, as in notification launcher programs.
- Most business reports use classic report events plus `FORM` routines for retrieval, processing, and output.
- UI-heavy tools may mix `FORM` routines with local classes for ALV events, drag and drop, or focused helper behavior.
- Notification programs commonly build typed payload data, generate JSON with `CALL TRANSFORMATION`, then send through a notification class.
- `STRANS` objects are part of the implementation style. When a report already uses a named transformation such as `ztool_*`, preserve that contract instead of replacing it with handwritten JSON.

### Preferred Structure

- Use classic section banners such as `Tables`, `Types`, `Variables`, `Select Screen`, `Initialization`, `Start Of Selection`, `Forms`.
- Keep one thin entry point, then delegate to small `FORM` routines.
- Let the top-level flow read like orchestration: retrieve, transform, display.
- Prefer local data flow through `USING` and `CHANGING` parameters instead of expanding global state.
- In UI programs, keep screen modules, ALV setup, and event handlers grouped together rather than scattering them.

### Indentation And Whitespace

- Use spaces for indentation by default. Do not introduce tab characters in generated or edited ABAP code unless the existing file already uses tabs consistently.
- In existing files, preserve the surrounding indentation style instead of normalizing unrelated lines.
- Never mix tabs and spaces within the same logical block.
- Favor whitespace that keeps classic report sections, `FORM` routines, and chained declarations easy to scan.

### Naming Rules

Use the BMW internal naming conventions below when the user asks for standardized naming, when creating new code, or when normalizing inconsistent declarations. These prefixes are mandatory for BMW-style code. ABAP is case-insensitive, so source may appear in upper or lower case, but the semantic prefix must stay intact.

#### Programs, Function Modules, Forms, Methods

- Selection-screen parameters: `p_*`
- Select-options: `s_*`
- Local constants: `lc_*`
- Global constants: `gc_*`
- Variable types: `tv_*`
- Structure types: `ts_*`
- Table types: `tt_*`
- Local scalar data and field symbols: `lv_*`, `<lv *>`
- Global scalar data and field symbols: `gv_*`, `<gv *>`
- Local structures and field symbols: `ls_*`, `<ls *>`
- Global structures and field symbols: `gs_*`, `<gs *>`
- Local internal tables and field symbols: `lt_*`, `<lt *>`
- Global internal tables and field symbols: `gt_*`, `<gt *>`
- Local ranges: `lt_*_r`
- Global ranges: `gt_*_r`
- Local references: `lr_*`, `lrs_*`, `lrt_*`, `lrc_*`
- Global references: `gr_*`, `grs_*`, `grt_*`, `grc_*`
- Local class definitions: `lcl_*`
- Global class definitions: `gcl_*`
- Local interface definitions: `lif_*`
- Global interface definitions: `gif_*`
- Static scalar attributes: `sv_*`
- Static structures: `ss_*`
- Static internal tables: `st_*`
- Static references: `sr_*`
- Event variables: `ev_*`
- Event structures: `es_*`
- Event tables: `et_*`
- Event references: `er_*`

#### Class-Specific Declarations

- Method-local data follows the same local prefixes: `lv_*`, `ls_*`, `lt_*`, `lr_*`
- Instance attributes:
  - Scalars: `mv_*`
  - Structures: `ms_*`
  - Internal tables: `mt_*`
  - References: `mr_*`
- Static class attributes:
  - Scalars: `sv_*`
  - Structures: `ss_*`
  - Internal tables: `st_*`
  - References: `sr_*`
- Constants declared inside methods use `lc_*`.
- Constants declared as class attributes use `gc_*`.

### Parameters

- Importing / `USING` parameters:
  - Scalars: `iv_*`
  - Structures: `is_*`
  - Internal tables: `it_*`
  - References: `ir_*`
- Exporting parameters:
  - Scalars: `ev_*`
  - Structures: `es_*`
  - Internal tables: `et_*`
  - References: `er_*`
- Changing parameters:
  - Scalars: `cv_*`
  - Structures: `cs_*`
  - Internal tables: `ct_*`
  - References: `cr_*`
- Returning parameters:
  - Scalars: `rv_*`
  - Structures: `rs_*`
  - Internal tables: `rt_*`
  - References: `rr_*`
- Legacy `TABLES` parameters should be avoided. If unavoidable, classify them semantically as `it_*`, `et_*`, or `ct_*`.

### Practical Notes

- Avoid plain `s_*` for statics because it conflicts with select-options. Use `sv_*`, `ss_*`, `st_*`, `sr_*`.
- For TOP includes or other global report areas, use the global prefixes such as `gc_*`, `gv_*`, `gs_*`, `grt_*`, `gcl_*`, `gif_*`.
- For subroutines that initialize and populate an output value internally, `ev_*` and `es_*` are valid even in classic `FORM ... CHANGING` usage.
- Apply the same parameter naming rules to web services as to function modules and class methods.
- Favor short semantic suffixes after the prefix, for example `lv_date`, `lt_items`, `iv_matnr`, `et_return`.

### Implementation Preferences

- Use procedural ABAP with `FORM` routines as the default style for report programs in this repo.
- Prefer modern ABAP expressions inside that classic structure: inline `DATA(...)`, `VALUE #( )`, `COND #( )`, `ASSIGNING FIELD-SYMBOL(...)`.
- Prefer direct use of standard ABAP statements, standard classes, and standard function modules over wrapping them in custom local helpers.
- Build display-related objects close to display logic, for example ALV field catalog next to the ALV call.
- Use text elements, icons, and typed output fields when they improve display semantics.
- Do not leave repeated or business-significant literals hardcoded in executable logic. Extract them into `CONSTANTS` with meaningful names.
- Prefer `CONSTANTS` for fixed statuses, options, default patterns, separators, message fragments, technical markers, and other stable literal values that carry intent.
- Keep literals inline only when they are truly one-off and self-evident, or when ABAP syntax requires the literal form directly and extracting it would reduce clarity.
- For ALV-heavy reports, local classes are acceptable for event handling, toolbar actions, drag/drop, or narrowly scoped helper behavior.
- For service integration reports, typed payload structures plus `CALL TRANSFORMATION` are preferred over ad hoc string assembly when a transformation object already exists.
- Keep persistence straightforward: `SELECT`, `MODIFY`, `COMMIT WORK` patterns are acceptable and common in this repo.

### Variable Definition Placement

- Declare variables at the beginning of each routine.
- In `FORM`, place `DATA`, `TYPES`, `CONSTANTS`, `FIELD-SYMBOLS`, and `STATICS` at the head of the routine, immediately after the `FORM` signature and parameter comments, before the first executable statement.
- In `METHOD`, place method-local declarations at the start of the method body, before business logic.
- Use the routine head as the default place for variables that are reused across multiple logical phases or need to stay visible for a broader part of the routine.
- Keep inline declarations when the variable is tightly bound to a single statement or a very small local block and the statement is clearer with the declaration in place.
- Do not force declarations out of inline ABAP source, iteration, lookup, assignment, exception, or transformation patterns when the statement reads better that way.
- This exception explicitly includes common patterns such as `SELECT ... INTO TABLE @DATA(...)`, `SELECT SINGLE ... INTO @DATA(...)`, `FETCH NEXT CURSOR ... INTO TABLE @DATA(...)`, `LOOP AT ... INTO DATA(...)`, `LOOP AT ... ASSIGNING FIELD-SYMBOL(...)`, `LOOP AT GROUP ... INTO DATA(...)`, `LOOP AT GROUP ... ASSIGNING FIELD-SYMBOL(...)`, `READ TABLE ... INTO DATA(...)`, `READ TABLE ... ASSIGNING FIELD-SYMBOL(...)`, `ASSIGN ... TO FIELD-SYMBOL(...)`, `CATCH ... INTO DATA(...)` and `CALL TRANSFORMATION ... RESULT XML DATA(...)`.
- The same applies to short-lived expression results or object references created directly on the statement, for example `DATA(lv_result) = ...`, `FINAL(lv_result) = ...`, `DATA(lr_obj) = NEW ...`, `DATA(lr_obj) = CAST ...`, or `DATA(lr_ref) = REF #(...)`.
- Keep an additional syntax and ATC boundary in mind: inline `DATA(...)` is acceptable only when ABAP can infer the type from the statement context. If a local variable needs an explicit `TYPE`, `LIKE`, `LENGTH`, or similar declaration form, do not simulate inline style with a mid-block `DATA ... TYPE ...` unless there is a strong reason.
- For explicitly typed locals that are still needed only in one branch, prefer routine-head declaration when that avoids ATC findings such as requiring declarations at the start of the `FORM` or `METHOD`.
- In practice: `DATA(lv_basic_text) = ...` is fine, but a companion variable like `lv_basic_auth` that must be declared as `TYPE string` should normally be declared at the beginning of the routine.
- Prefer judging whether a declaration should move by scope and readability, not by whether it is technically possible to hoist it to the routine head.
- Avoid mid-block declarations in branches (`IF`, `CASE`, `LOOP`) unless there is a strong scoping reason.

### Loop Work Area Handling

- Prefer `LOOP ... ASSIGNING FIELD-SYMBOL(<ls_...>)` over `LOOP ... INTO ls_...` when possible.
- This pattern is preferred for both performance and cleaner code flow because no extra work-area reset is needed.
- If `LOOP ... INTO` is used with a reusable work area, clear the work area (or relevant fields) before the end of the loop iteration to avoid carry-over side effects.
- Avoid relying on implicit overwrite behavior when subsequent logic depends on fields that may stay populated from prior iterations.

### Internal Table Cleanup

- Free large internal tables at the end of the main processing routine (program ending section) to release memory explicitly.
- Prefer a single grouped cleanup statement near routine end, for example `FREE: lt_a, lt_b, lt_c` when those tables are no longer needed.
- Apply this especially for staging/result tables created in orchestration forms (for example create/update entry flows).
- Keep cleanup at a stable end position; avoid scattering `FREE` statements across many branches unless early release is required for memory pressure.

### Selection screen

- Use `text-...` after `WITH FRAME TITLE` to maintain the title.

### Screen And UI Habits

- Selection screens are used as the main interaction surface for many tools.
- Dynamic screen behavior with `AT SELECTION-SCREEN OUTPUT` and `LOOP AT SCREEN` is a normal pattern here.
- Custom function keys, pushbuttons, docking containers, and text editors are valid project-style solutions for utility reports.
- Literal UI text is used in places. Do not force a text-element migration unless the user asks.

### Display Text Versus Technical Identifiers

- Distinguish consistently between human-facing labels and technical identifiers.
- Prefer `text-xxx` text elements for stable UI labels that users read, especially ALV `coltext`, selection-screen frame titles, pushbutton text, popup titles, list headings, and other display descriptions.
- Keep technical identifiers as literal technical names when the value is used for binding, lookup, or metadata, for example ALV `fieldname`, structure component names, parameter names, DDIC field names, program names, variant names, or keys.
- Do not convert technical identifiers to text elements just to mirror the neighboring display label. Mixed patterns such as `fieldname` → `JOBNAME` together with `coltext = text-001` are preferred when one side is technical and the other is user-facing.
- Apply this rule beyond ALV field catalogs: whenever one attribute is a machine-readable identifier and another is a user-facing description, only the description should be text-managed.
- If a user-facing label is clearly one-off, internal, or not worth maintaining as a text element, keeping a short literal string is acceptable. Do not mass-migrate existing literals unless the user asks.

### Comment Style

- Assume ATC checks are active by default in this repository unless the user explicitly says otherwise.
- Keep the large section banners.
- Add `FORM` header comments for parameter usage as the default style, and keep the header focused on the parameters rather than the full routine logic.
- For `FORM` routines with `USING`, `CHANGING`, or `TABLES` parameters, add explicit parameter usage comments so ATC checks such as "Add comment for subroutine parameter usage" are satisfied.
- Use `*` for `USING` parameters and `<--...` for `CHANGING` parameters. If `TABLES` is unavoidable, document it explicitly with `<--...`.
- Inside executable code, do not use `"` comment lines for normal logic comments. Use standalone `*` comment lines instead.
- Put the overall business or technical logic of the `FORM` inside the routine as short block comments before the relevant executable sections, not in the header comment block above `FORM`.
- Each major logical phase should have at least one short comment line ahead of it, for example configuration read, validation, paging, aggregation, output build, persistence, or cleanup.
- Treat comment coverage as a quantitative requirement, not just a readability preference. For routines with more than roughly 30 to 35 executable statements, add enough short block comments so the ratio of comment lines to executable statements stays at or above 10%.
- For long routines, spread comment lines across the main logical phases instead of placing only one or two comments near the top.
- When there is any doubt about local ATC thresholds, prefer adding one or two extra standalone comment lines in long routines instead of risking a comment-density finding.
- Add short field comments only where the field meaning is not obvious from the type.
- Avoid noisy inline comments. Only comment when it helps the reader understand intent or display semantics.

### Avoid

- Do not refactor a report into local classes unless the user explicitly asks.
- Do not introduce broad utility helpers for simple conversions or table access.
- Do not spread one display concern across multiple distant forms when it can stay local.
- Do not rename established business-facing identifiers without a clear reason.
- Do not introduce new hardcoded business or technical literals when a named `CONSTANTS` declaration would make the intent explicit.

### Working Pattern

When modifying a report, prefer this sequence:

1. Preserve or restore the sectioned report layout.
2. Keep `START-OF-SELECTION` thin.
3. Split retrieval, transformation, and display into separate `FORM`s.
4. Pass data explicitly between forms.
5. Keep naming aligned with the BMW prefix convention for locals, globals, parameters, types, references, and class attributes.
6. Place ALV or output configuration near the final display routine.
7. If the report already uses local classes, keep them focused on UI events or bounded helper logic.
8. If the report integrates with notifications, preserve the existing pattern of typed payload, transformation, config selection, send, and free.

### Minimal Template (example)

```abap
REPORT zexample.

*&-----------------------------------------------------------------
*&                    Types
*&-----------------------------------------------------------------
TYPES: BEGIN OF ts_data,
        field1 TYPE char20,
       END OF ts_data,
       tt_data TYPE STANDARD TABLE OF ts_data WITH EMPTY KEY.

*&-----------------------------------------------------------------
*&                    Start of Selection
*&-----------------------------------------------------------------
START-OF-SELECTION.
  PERFORM retrieve.

FORM retrieve.
  DATA lt_data TYPE tt_data.

  " Build the working data for the report.
  PERFORM build_data CHANGING lt_data.

  " Hand over the prepared rows to the output step.
  PERFORM display USING lt_data.
ENDFORM.

*&-----------------------------------------------------------------
*& Form build_data
*&-----------------------------------------------------------------
*   <-- ct_data    Output rows for display
*&-----------------------------------------------------------------
FORM build_data CHANGING ct_data TYPE tt_data.

  " Collect the rows required for the current run.
  APPEND VALUE #( field1 = 'Demo' ) TO ct_data.
ENDFORM.

*&-----------------------------------------------------------------
*& Form display
*&-----------------------------------------------------------------
*   --> it_data   Prepared rows for output
*&-----------------------------------------------------------------
FORM display USING it_data TYPE tt_data.

  " Render the prepared result set.
  LOOP AT it_data ASSIGNING FIELD-SYMBOL(<ls_data>).
    WRITE: / <ls_data>-field1.
  ENDLOOP.
ENDFORM.
```