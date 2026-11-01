CLASS zcl_crw_report_svc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_group,
             key   TYPE string,
             count TYPE i,
           END OF ty_group.
    TYPES tt_group TYPE STANDARD TABLE OF ty_group WITH EMPTY KEY.

    TYPES: BEGIN OF ty_trend,
             date    TYPE string,
             created TYPE i,
             closed  TYPE i,
           END OF ty_trend.
    TYPES tt_trend TYPE STANDARD TABLE OF ty_trend WITH EMPTY KEY.

    TYPES: BEGIN OF ty_changes,
             by_status   TYPE tt_group,
             by_type     TYPE tt_group,
             by_priority TYPE tt_group,
             trend       TYPE tt_trend,
           END OF ty_changes.

    TYPES: BEGIN OF ty_duration,
             avg_hours TYPE i,
             min_hours TYPE i,
             max_hours TYPE i,
             count     TYPE i,
           END OF ty_duration.

    TYPES: BEGIN OF ty_duration_rpt,
             approval TYPE ty_duration,
             closure  TYPE ty_duration,
           END OF ty_duration_rpt.

    TYPES: BEGIN OF ty_overdue,
             kind        TYPE string,
             object_type TYPE string,
             object_id   TYPE string,
             display_id  TYPE string,
             title       TYPE string,
             due_at      TYPE string,
             days_overdue TYPE i,
           END OF ty_overdue.
    TYPES tt_overdue TYPE STANDARD TABLE OF ty_overdue WITH EMPTY KEY.

    TYPES: BEGIN OF ty_funnel,
             stage TYPE string,
             count TYPE i,
           END OF ty_funnel.
    TYPES tt_funnel TYPE STANDARD TABLE OF ty_funnel WITH EMPTY KEY.

    TYPES: BEGIN OF ty_toc_item,
             trkorr        TYPE string,
             cd_id         TYPE string,
             target_system TYPE string,
             tr_status     TYPE string,
             imported_at   TYPE string,
             retrofit_state TYPE string,
           END OF ty_toc_item.
    TYPES tt_toc_items TYPE STANDARD TABLE OF ty_toc_item WITH EMPTY KEY.

    TYPES: BEGIN OF ty_toc,
             funnel TYPE tt_funnel,
             items  TYPE tt_toc_items,
           END OF ty_toc.

    CONSTANTS gc_trend_days TYPE i VALUE 14.

    CLASS-METHODS changes
      RETURNING VALUE(rs_report) TYPE ty_changes.

    CLASS-METHODS duration
      RETURNING VALUE(rs_report) TYPE ty_duration_rpt.

    CLASS-METHODS overdue
      RETURNING VALUE(rt_items) TYPE tt_overdue.

    CLASS-METHODS to_c
      RETURNING VALUE(rs_report) TYPE ty_toc.

    CLASS-METHODS csv
      IMPORTING iv_kind        TYPE string
      RETURNING VALUE(rv_csv)  TYPE string.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_db_group,
             key   TYPE char20,
             count TYPE i,
           END OF ty_db_group.
    TYPES tt_db_groups TYPE STANDARD TABLE OF ty_db_group WITH EMPTY KEY.

    CLASS-METHODS seconds_between
      IMPORTING iv_from        TYPE char14
                iv_to          TYPE char14
      RETURNING VALUE(rv_seconds) TYPE i.

    CLASS-METHODS collect_groups
      IMPORTING it_db            TYPE tt_db_groups
      RETURNING VALUE(rt_groups) TYPE tt_group.

    CLASS-METHODS build_duration
      IMPORTING iv_total_seconds TYPE i
                iv_count        TYPE i
                iv_min_seconds  TYPE i
                iv_max_seconds  TYPE i
      RETURNING VALUE(rs_duration) TYPE ty_duration.
ENDCLASS.

CLASS zcl_crw_report_svc IMPLEMENTATION.
  METHOD changes.
    DATA lt_db TYPE tt_db_groups.
    DATA lv_offset TYPE i.
    DATA lv_day TYPE d.
    DATA lv_from TYPE char14.
    DATA lv_to TYPE char14.
    DATA lv_count TYPE i.

    SELECT status AS key, COUNT(*) AS count
      FROM zcrw_req
      GROUP BY status
      INTO TABLE @lt_db.
    rs_report-by_status = collect_groups( lt_db ).

    REFRESH lt_db.
    SELECT req_type AS key, COUNT(*) AS count
      FROM zcrw_req
      GROUP BY req_type
      INTO TABLE @lt_db.
    rs_report-by_type = collect_groups( lt_db ).

    REFRESH lt_db.
    SELECT priority AS key, COUNT(*) AS count
      FROM zcrw_req
      GROUP BY priority
      INTO TABLE @lt_db.
    rs_report-by_priority = collect_groups( lt_db ).

*   Daily created / closed counts for the trend window.
    lv_offset = gc_trend_days - 1.
    WHILE lv_offset >= 0.
      lv_day = sy-datum - lv_offset.
      lv_from = |{ lv_day }000000|.
      lv_to = |{ lv_day }235959|.

      SELECT COUNT(*) FROM zcrw_req
        WHERE created_at BETWEEN @lv_from AND @lv_to
        INTO @lv_count.
      DATA(lv_created) = lv_count.

      SELECT COUNT(*) FROM zcrw_req
        WHERE closed_at BETWEEN @lv_from AND @lv_to
          AND closed_at <> ''
        INTO @lv_count.
      DATA(lv_closed) = lv_count.

      APPEND VALUE #( date    = zcl_crw_json=>format_date( lv_day )
                      created = lv_created
                      closed  = lv_closed ) TO rs_report-trend.
      lv_offset = lv_offset - 1.
    ENDWHILE.
  ENDMETHOD.

  METHOD duration.
    DATA lt_steps TYPE STANDARD TABLE OF zcrw_appr WITH EMPTY KEY.
    DATA lt_requests TYPE STANDARD TABLE OF zcrw_req WITH EMPTY KEY.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_min TYPE i.
    DATA lv_max TYPE i.
    DATA lv_seconds TYPE i.

*   Approval step duration: created_at -> decided_at for approved steps.
    SELECT * FROM zcrw_appr
      WHERE appr_state = 'APPROVED' AND decided_at <> ''
      INTO TABLE @lt_steps.

    LOOP AT lt_steps ASSIGNING FIELD-SYMBOL(<ls_step>).
      lv_seconds = seconds_between( iv_from = <ls_step>-created_at iv_to = <ls_step>-decided_at ).
      IF lv_seconds < 0.
        CONTINUE.
      ENDIF.
      lv_total = lv_total + lv_seconds.
      lv_count = lv_count + 1.
      IF lv_count = 1 OR lv_seconds < lv_min.
        lv_min = lv_seconds.
      ENDIF.
      IF lv_seconds > lv_max.
        lv_max = lv_seconds.
      ENDIF.
    ENDLOOP.

    rs_report-approval = build_duration( iv_total_seconds = lv_total iv_count = lv_count iv_min_seconds = lv_min iv_max_seconds = lv_max ).

*   Closure duration: created_at -> closed_at for closed requests.
    CLEAR: lv_total, lv_count, lv_min, lv_max.
    SELECT * FROM zcrw_req
      WHERE status = 'CLOSED' AND closed_at <> ''
      INTO TABLE @lt_requests.

    LOOP AT lt_requests ASSIGNING FIELD-SYMBOL(<ls_req>).
      lv_seconds = seconds_between( iv_from = <ls_req>-created_at iv_to = <ls_req>-closed_at ).
      IF lv_seconds < 0.
        CONTINUE.
      ENDIF.
      lv_total = lv_total + lv_seconds.
      lv_count = lv_count + 1.
      IF lv_count = 1 OR lv_seconds < lv_min.
        lv_min = lv_seconds.
      ENDIF.
      IF lv_seconds > lv_max.
        lv_max = lv_seconds.
      ENDIF.
    ENDLOOP.

    rs_report-closure = build_duration( iv_total_seconds = lv_total iv_count = lv_count iv_min_seconds = lv_min iv_max_seconds = lv_max ).
  ENDMETHOD.

  METHOD overdue.
    DATA lt_tasks TYPE STANDARD TABLE OF zcrw_task WITH EMPTY KEY.
    DATA lt_sched TYPE STANDARD TABLE OF zcrw_sched WITH EMPTY KEY.
    DATA lv_now TYPE char14.
    DATA lv_title TYPE string.
    DATA lv_days TYPE i.
    DATA lv_due TYPE dats.
    DATA lv_today TYPE dats.

    lv_now = zcl_crw_util=>now( ).
    lv_today = sy-datum.

*   Tasks past their due date and not finished.
    SELECT * FROM zcrw_task
      WHERE due_date < @lv_today
        AND status <> 'DONE'
        AND status <> 'CANCELLED'
      INTO TABLE @lt_tasks.

    LOOP AT lt_tasks ASSIGNING FIELD-SYMBOL(<ls_task>).
      APPEND VALUE #( kind         = 'TASK'
                      object_type  = 'TASK'
                      object_id    = <ls_task>-task_id
                      display_id   = |T-{ <ls_task>-task_id }|
                      title        = <ls_task>-title
                      due_at       = zcl_crw_json=>format_date( <ls_task>-due_date )
                      days_overdue = lv_today - <ls_task>-due_date ) TO rt_items.
    ENDLOOP.

*   Import schedules that are due but not confirmed.
    SELECT * FROM zcrw_sched
      WHERE status = 'PLANNED'
        AND scheduled_at < @lv_now
      INTO TABLE @lt_sched.

    LOOP AT lt_sched ASSIGNING FIELD-SYMBOL(<ls_sched>).
      lv_title = <ls_sched>-note.
      IF <ls_sched>-object_type = 'CD'.
        SELECT SINGLE title FROM zcrw_cd WHERE cd_id = @<ls_sched>-object_id INTO @lv_title.
      ELSE.
        lv_title = <ls_sched>-object_id.
      ENDIF.
      lv_due = substring( val = <ls_sched>-scheduled_at len = 8 ).
      lv_days = lv_today - lv_due.
      IF lv_days < 0.
        lv_days = 0.
      ENDIF.
      APPEND VALUE #( kind         = 'SCHEDULE'
                      object_type  = <ls_sched>-object_type
                      object_id    = <ls_sched>-object_id
                      display_id   = |{ <ls_sched>-object_id }|
                      title        = lv_title
                      due_at       = zcl_crw_json=>format_timestamp( <ls_sched>-scheduled_at )
                      days_overdue = lv_days ) TO rt_items.
    ENDLOOP.
  ENDMETHOD.

  METHOD to_c.
    DATA lt_rows TYPE STANDARD TABLE OF zcrw_tr WITH EMPTY KEY.
    DATA lv_count TYPE i.
    DATA lv_scheduled TYPE i.

    SELECT * FROM zcrw_tr WHERE tr_kind = 'TOC' INTO TABLE @lt_rows.

    APPEND VALUE #( stage = 'LINKED' count = lines( lt_rows ) ) TO rs_report-funnel.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_tr>).
      IF <ls_tr>-tr_status = 'R'.
        lv_count = lv_count + 1.
      ENDIF.
    ENDLOOP.
    APPEND VALUE #( stage = 'RELEASED' count = lv_count ) TO rs_report-funnel.

    SELECT COUNT(*) FROM zcrw_sched
      WHERE object_type = 'TOC' AND status <> 'CANCELLED'
      INTO @lv_scheduled.
    APPEND VALUE #( stage = 'IMPORT_SCHEDULED' count = lv_scheduled ) TO rs_report-funnel.

    CLEAR lv_count.
    LOOP AT lt_rows ASSIGNING <ls_tr>.
      IF <ls_tr>-imported_at IS NOT INITIAL.
        lv_count = lv_count + 1.
      ENDIF.
    ENDLOOP.
    APPEND VALUE #( stage = 'IMPORTED' count = lv_count ) TO rs_report-funnel.

    LOOP AT lt_rows ASSIGNING <ls_tr>.
      APPEND VALUE #( trkorr         = <ls_tr>-trkorr
                      cd_id          = <ls_tr>-cd_id
                      target_system  = <ls_tr>-tarsystem
                      tr_status      = <ls_tr>-tr_status
                      imported_at    = zcl_crw_json=>format_timestamp( <ls_tr>-imported_at )
                      retrofit_state = <ls_tr>-retrofit_state ) TO rs_report-items.
    ENDLOOP.
  ENDMETHOD.

  METHOD csv.
    DATA lv_csv TYPE string.
    DATA lv_nl TYPE string.
    DATA lt_groups TYPE tt_group.
    DATA lt_overdue TYPE tt_overdue.
    DATA ls_toc TYPE ty_toc.

    lv_nl = cl_abap_char_utilities=>newline.

    CASE iv_kind.
      WHEN 'overdue'.
        lv_csv = |kind,objectType,objectId,displayId,title,dueAt,daysOverdue{ lv_nl }|.
        lt_overdue = overdue( ).
        LOOP AT lt_overdue ASSIGNING FIELD-SYMBOL(<ls_overdue>).
          lv_csv = lv_csv && |{ <ls_overdue>-kind },{ <ls_overdue>-object_type },{ <ls_overdue>-object_id }| &&
                   |,{ <ls_overdue>-display_id },"{ <ls_overdue>-title }",{ <ls_overdue>-due_at },{ <ls_overdue>-days_overdue }{ lv_nl }|.
        ENDLOOP.
      WHEN 'toc'.
        DATA lt_toc_items TYPE tt_toc_items.
        lv_csv = |trkorr,cdId,targetSystem,trStatus,importedAt,retrofitState{ lv_nl }|.
        ls_toc = to_c( ).
        lt_toc_items = ls_toc-items.
        LOOP AT lt_toc_items ASSIGNING FIELD-SYMBOL(<ls_toc>).
          lv_csv = lv_csv && |{ <ls_toc>-trkorr },{ <ls_toc>-cd_id },{ <ls_toc>-target_system }| &&
                   |,{ <ls_toc>-tr_status },{ <ls_toc>-imported_at },{ <ls_toc>-retrofit_state }{ lv_nl }|.
        ENDLOOP.
      WHEN 'duration'.
        DATA ls_duration TYPE ty_duration_rpt.
        ls_duration = duration( ).
        lv_csv = |scope,avgHours,minHours,maxHours,count{ lv_nl }|.
        lv_csv = lv_csv && |approval,{ ls_duration-approval-avg_hours },{ ls_duration-approval-min_hours }| &&
                 |,{ ls_duration-approval-max_hours },{ ls_duration-approval-count }{ lv_nl }|.
        lv_csv = lv_csv && |closure,{ ls_duration-closure-avg_hours },{ ls_duration-closure-min_hours }| &&
                 |,{ ls_duration-closure-max_hours },{ ls_duration-closure-count }{ lv_nl }|.
      WHEN OTHERS.
        DATA ls_changes TYPE ty_changes.
        lv_csv = |group,key,count{ lv_nl }|.
        ls_changes = changes( ).
        lt_groups = ls_changes-by_status.
        LOOP AT lt_groups ASSIGNING FIELD-SYMBOL(<ls_group>).
          lv_csv = lv_csv && |status,{ <ls_group>-key },{ <ls_group>-count }{ lv_nl }|.
        ENDLOOP.
        lt_groups = ls_changes-by_type.
        LOOP AT lt_groups ASSIGNING FIELD-SYMBOL(<ls_type>).
          lv_csv = lv_csv && |type,{ <ls_type>-key },{ <ls_type>-count }{ lv_nl }|.
        ENDLOOP.
    ENDCASE.

    rv_csv = lv_csv.
  ENDMETHOD.

  METHOD seconds_between.
    DATA lv_from_date TYPE d.
    DATA lv_from_time TYPE t.
    DATA lv_to_date TYPE d.
    DATA lv_to_time TYPE t.

    IF iv_from IS INITIAL OR iv_to IS INITIAL.
      RETURN.
    ENDIF.

    lv_from_date = substring( val = iv_from len = 8 ).
    lv_from_time = substring( val = iv_from off = 8 len = 6 ).
    lv_to_date = substring( val = iv_to len = 8 ).
    lv_to_time = substring( val = iv_to off = 8 len = 6 ).

    rv_seconds = ( lv_to_date - lv_from_date ) * 86400 + ( lv_to_time - lv_from_time ).
  ENDMETHOD.

  METHOD collect_groups.
    LOOP AT it_db ASSIGNING FIELD-SYMBOL(<ls_db>).
      APPEND VALUE #( key = CONV string( <ls_db>-key ) count = <ls_db>-count ) TO rt_groups.
    ENDLOOP.
  ENDMETHOD.

  METHOD build_duration.
    IF iv_count = 0.
      RETURN.
    ENDIF.

    rs_duration-count = iv_count.
    rs_duration-avg_hours = iv_total_seconds / iv_count / 3600.
    rs_duration-min_hours = iv_min_seconds / 3600.
    rs_duration-max_hours = iv_max_seconds / 3600.
  ENDMETHOD.
ENDCLASS.
