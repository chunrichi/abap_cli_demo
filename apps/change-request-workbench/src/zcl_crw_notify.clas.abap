CLASS zcl_crw_notify DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.

    CONSTANTS: gc_type_approval_pending  TYPE string VALUE 'APPROVAL_PENDING',
               gc_type_approval_rejected TYPE string VALUE 'APPROVAL_REJECTED',
               gc_type_task_overdue      TYPE string VALUE 'TASK_OVERDUE',
               gc_type_sched_overdue     TYPE string VALUE 'SCHED_OVERDUE',
               gc_type_info              TYPE string VALUE 'INFO',
               gc_status_unread          TYPE zcrw_notify-status VALUE 'UNREAD',
               gc_status_read            TYPE zcrw_notify-status VALUE 'READ',
               gc_status_dismissed       TYPE zcrw_notify-status VALUE 'DISMISSED',
               gc_severity_info          TYPE string VALUE 'INFO',
               gc_severity_warn          TYPE string VALUE 'WARN',
               gc_severity_critical      TYPE string VALUE 'CRITICAL',
               gc_source_event           TYPE string VALUE 'EVENT',
               gc_source_scan            TYPE string VALUE 'SCAN',
               gc_source_api             TYPE string VALUE 'API',
               gc_max_scan_rows          TYPE i VALUE 500.

    TYPES tt_notifications TYPE STANDARD TABLE OF zcrw_notify WITH EMPTY KEY.

    TYPES: BEGIN OF ty_list,
             items TYPE tt_notifications,
             total TYPE i,
           END OF ty_list.

    TYPES: BEGIN OF ty_create_result,
             notify_id TYPE zcrw_notify-notify_id,
             created   TYPE abap_bool,
           END OF ty_create_result.

    TYPES: BEGIN OF ty_scan_result,
             approval_created TYPE i,
             task_created     TYPE i,
             schedule_created TYPE i,
             total_created    TYPE i,
           END OF ty_scan_result.

    CLASS-METHODS emit
      IMPORTING iv_user         TYPE string
                iv_type         TYPE string
                iv_object_type  TYPE string DEFAULT ''
                iv_object_id    TYPE string DEFAULT ''
                iv_title        TYPE string
                iv_message      TYPE string DEFAULT ''
                iv_link_page    TYPE string DEFAULT ''
                iv_severity     TYPE string DEFAULT gc_severity_info
                iv_dedup_key    TYPE string DEFAULT ''
                iv_source       TYPE string DEFAULT gc_source_api
      RETURNING VALUE(rs_result) TYPE ty_create_result
      RAISING   zcx_crw_error.

    CLASS-METHODS refresh_for_user
      IMPORTING iv_user           TYPE string
      RETURNING VALUE(rv_created) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS run_scan
      RETURNING VALUE(rs_result) TYPE ty_scan_result
      RAISING   zcx_crw_error.

    CLASS-METHODS list_for_user
      IMPORTING iv_user           TYPE string
                iv_status         TYPE string DEFAULT ''
                iv_type           TYPE string DEFAULT ''
                iv_page           TYPE i DEFAULT 1
                iv_page_size      TYPE i DEFAULT 20
      RETURNING VALUE(rs_result) TYPE ty_list.

    CLASS-METHODS unread_count
      IMPORTING iv_user          TYPE string
      RETURNING VALUE(rv_count)  TYPE i.

    CLASS-METHODS mark_read
      IMPORTING iv_user          TYPE string
                iv_notify_id     TYPE string
      RETURNING VALUE(rv_updated) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS mark_all_read
      IMPORTING iv_user           TYPE string
      RETURNING VALUE(rv_updated) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS notify_approval_pending
      IMPORTING is_step TYPE zcrw_appr.

    CLASS-METHODS notify_approval_rejected
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
                iv_appr_id     TYPE string
                iv_comment     TYPE string.

    CLASS-METHODS type_is_valid
      IMPORTING iv_type          TYPE string
      RETURNING VALUE(rv_valid)  TYPE abap_bool.

    CLASS-METHODS object_display_id
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_id)   TYPE string.

  PRIVATE SECTION.
    CLASS-METHODS notification_exists
      IMPORTING iv_user       TYPE string
                iv_dedup_key  TYPE string
      RETURNING VALUE(rv_exists) TYPE abap_bool.

    CLASS-METHODS object_title
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_title) TYPE string.

    CLASS-METHODS object_requester
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_user) TYPE string.

    CLASS-METHODS object_link
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
      RETURNING VALUE(rv_link) TYPE string.

    CLASS-METHODS user_has_scan_role
      IMPORTING iv_user          TYPE string
      RETURNING VALUE(rv_has)    TYPE abap_bool.

    CLASS-METHODS deliver_email
      IMPORTING is_notify        TYPE zcrw_notify
      RETURNING VALUE(rv_sent)   TYPE abap_bool.

    CLASS-METHODS truncate
      IMPORTING iv_text         TYPE string
                iv_length       TYPE i
      RETURNING VALUE(rv_text)  TYPE string.
ENDCLASS.

CLASS zcl_crw_notify IMPLEMENTATION.
  METHOD emit.
    DATA ls_notify TYPE zcrw_notify.
    DATA lv_user TYPE zcrw_notify-user_id.
    DATA lv_dedup TYPE zcrw_notify-dedup_key.

*   Validate the notification contract before touching the database.
    IF iv_user IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Notification user is required'.
    ENDIF.
    IF iv_title IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Notification title is required'.
    ENDIF.
    IF type_is_valid( iv_type ) = abap_false.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = |Unknown notification type { iv_type }|.
    ENDIF.

*   A dedicated dedup key keeps scans and event hooks idempotent.
    lv_user = iv_user.
    lv_dedup = iv_dedup_key.
    IF lv_dedup IS NOT INITIAL AND notification_exists( iv_user = iv_user iv_dedup_key = iv_dedup_key ) = abap_true.
      IF iv_dedup_key IS NOT INITIAL.
        SELECT SINGLE notify_id FROM zcrw_notify
          WHERE user_id = @lv_user AND dedup_key = @lv_dedup
          INTO @rs_result-notify_id.
      ENDIF.
      rs_result-created = abap_false.
      RETURN.
    ENDIF.

*   Build and persist the notification row.
    ls_notify-notify_id   = zcl_crw_util=>uuid( ).
    IF ls_notify-notify_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOTIFY_UUID' iv_text = 'Could not create a notification id'.
    ENDIF.
    ls_notify-user_id     = iv_user.
    ls_notify-notify_type = iv_type.
    ls_notify-object_type = iv_object_type.
    ls_notify-object_id   = truncate( iv_text = iv_object_id iv_length = 20 ).
    ls_notify-title       = truncate( iv_text = iv_title iv_length = 80 ).
    ls_notify-message     = truncate( iv_text = iv_message iv_length = 255 ).
    ls_notify-link_page   = truncate( iv_text = iv_link_page iv_length = 80 ).
    ls_notify-severity    = iv_severity.
    ls_notify-status      = gc_status_unread.
    ls_notify-dedup_key   = truncate( iv_text = iv_dedup_key iv_length = 80 ).
    ls_notify-source      = iv_source.
    ls_notify-created_at  = zcl_crw_util=>now( ).
    ls_notify-created_by  = sy-uname.

    INSERT zcrw_notify FROM ls_notify.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOTIFY_INSERT' iv_text = 'Could not write the notification row'.
    ENDIF.

    rs_result-notify_id = ls_notify-notify_id.
    rs_result-created = abap_true.

*   Reserved external channel: SMTP is not configured in the current environment.
    deliver_email( ls_notify ).
  ENDMETHOD.

  METHOD refresh_for_user.
    DATA lv_user TYPE zcrw_notify-user_id.
    DATA lv_now TYPE char14.
    DATA lv_today TYPE dats.
    DATA lt_appr TYPE STANDARD TABLE OF zcrw_appr WITH EMPTY KEY.
    DATA lt_task TYPE STANDARD TABLE OF zcrw_task WITH EMPTY KEY.
    DATA lt_sched TYPE STANDARD TABLE OF zcrw_sched WITH EMPTY KEY.
    DATA ls_created TYPE ty_create_result.

    lv_user = iv_user.
    lv_now = zcl_crw_util=>now( ).
    lv_today = sy-datum.

*   Pending approval steps assigned to the user.
    SELECT * FROM zcrw_appr
      WHERE approver = @lv_user AND appr_state = 'PENDING'
      INTO TABLE @lt_appr UP TO @gc_max_scan_rows ROWS.
    LOOP AT lt_appr ASSIGNING FIELD-SYMBOL(<ls_appr>).
      TRY.
          DATA(lv_display) = object_display_id( iv_object_type = CONV string( <ls_appr>-object_type )
                                               iv_object_id   = CONV string( <ls_appr>-object_id ) ).
          DATA(lv_title) = object_title( iv_object_type = CONV string( <ls_appr>-object_type )
                                         iv_object_id   = CONV string( <ls_appr>-object_id ) ).
          CALL METHOD zcl_crw_notify=>emit
            EXPORTING
              iv_user        = CONV string( lv_user )
              iv_type        = gc_type_approval_pending
              iv_object_type = CONV string( <ls_appr>-object_type )
              iv_object_id   = CONV string( <ls_appr>-object_id )
              iv_title       = |待审批：{ lv_display }|
              iv_message     = |{ lv_title }（审批步骤 { <ls_appr>-step_no }）|
              iv_link_page   = '#/approvals'
              iv_severity    = gc_severity_info
              iv_dedup_key   = |APPR:{ <ls_appr>-appr_id }|
              iv_source      = gc_source_scan
            RECEIVING
              rs_result      = ls_created.
          IF ls_created-created = abap_true.
            rv_created = rv_created + 1.
          ENDIF.
        CATCH zcx_crw_error.
          CONTINUE.
      ENDTRY.
    ENDLOOP.

*   Overdue tasks assigned to the user.
    SELECT * FROM zcrw_task
      WHERE assignee = @lv_user
        AND due_date < @lv_today
        AND due_date <> '00000000'
        AND status <> 'DONE'
        AND status <> 'CANCELLED'
      INTO TABLE @lt_task UP TO @gc_max_scan_rows ROWS.
    LOOP AT lt_task ASSIGNING FIELD-SYMBOL(<ls_task>).
      TRY.
          CALL METHOD zcl_crw_notify=>emit
            EXPORTING
              iv_user = CONV string( lv_user )
              iv_type = gc_type_task_overdue
              iv_object_type = 'TASK'
              iv_object_id = CONV string( <ls_task>-task_id )
              iv_title = |任务逾期：{ object_display_id( iv_object_type = 'TASK'
              iv_object_id = CONV string( <ls_task>-task_id ) ) }|
              iv_message = |{ <ls_task>-title }（截止 { <ls_task>-due_date }）|
              iv_link_page = '#/tasks'
              iv_severity = gc_severity_warn
              iv_dedup_key = |TASK_OVERDUE:{ <ls_task>-task_id }:{ <ls_task>-due_date }|
              iv_source = gc_source_scan
            RECEIVING
              rs_result      = ls_created.
          IF ls_created-created = abap_true.
            rv_created = rv_created + 1.
          ENDIF.
        CATCH zcx_crw_error.
          CONTINUE.
      ENDTRY.
    ENDLOOP.

*   Overdue import schedules are global; only planners get the reminder.
    IF user_has_scan_role( iv_user = iv_user ) = abap_true.
      SELECT * FROM zcrw_sched
        WHERE status = 'PLANNED' AND scheduled_at < @lv_now AND scheduled_at <> ''
        INTO TABLE @lt_sched UP TO @gc_max_scan_rows ROWS.
      LOOP AT lt_sched ASSIGNING FIELD-SYMBOL(<ls_sched>).
        TRY.
            CALL METHOD zcl_crw_notify=>emit
              EXPORTING
                iv_user = CONV string( lv_user )
                iv_type = gc_type_sched_overdue
                iv_object_type = 'SCHED'
                iv_object_id = CONV string( <ls_sched>-sched_id )
                iv_title = |导入计划逾期：{ <ls_sched>-object_id }|
                iv_message = |计划于 { <ls_sched>-scheduled_at } 导入 { <ls_sched>-target_sys }，尚未确认|
                iv_link_page = '#/schedule'
                iv_severity = gc_severity_warn
                iv_dedup_key = |SCHED_OVERDUE:{ <ls_sched>-sched_id }:{ <ls_sched>-scheduled_at }|
                iv_source = gc_source_scan
              RECEIVING
                rs_result      = ls_created.
            IF ls_created-created = abap_true.
              rv_created = rv_created + 1.
            ENDIF.
          CATCH zcx_crw_error.
            CONTINUE.
        ENDTRY.
      ENDLOOP.
    ENDIF.
  ENDMETHOD.

  METHOD run_scan.
    DATA lv_now TYPE char14.
    DATA lv_today TYPE dats.
    DATA lt_appr TYPE STANDARD TABLE OF zcrw_appr WITH EMPTY KEY.
    DATA lt_task TYPE STANDARD TABLE OF zcrw_task WITH EMPTY KEY.
    DATA lt_sched TYPE STANDARD TABLE OF zcrw_sched WITH EMPTY KEY.
    DATA lt_users TYPE string_table.
    DATA lt_scan_roles TYPE string_table.
    DATA ls_created TYPE ty_create_result.

    lv_now = zcl_crw_util=>now( ).
    lv_today = sy-datum.

*   Notify every assignee of a pending approval step.
    SELECT * FROM zcrw_appr
      WHERE appr_state = 'PENDING' AND approver <> ''
      INTO TABLE @lt_appr UP TO @gc_max_scan_rows ROWS.
    LOOP AT lt_appr ASSIGNING FIELD-SYMBOL(<ls_appr>).
      TRY.
          DATA(lv_display) = object_display_id( iv_object_type = CONV string( <ls_appr>-object_type )
                                               iv_object_id   = CONV string( <ls_appr>-object_id ) ).
          DATA(lv_title) = object_title( iv_object_type = CONV string( <ls_appr>-object_type )
                                         iv_object_id   = CONV string( <ls_appr>-object_id ) ).
          CALL METHOD zcl_crw_notify=>emit
            EXPORTING
              iv_user = CONV string( <ls_appr>-approver )
              iv_type = gc_type_approval_pending
              iv_object_type = CONV string( <ls_appr>-object_type )
              iv_object_id = CONV string( <ls_appr>-object_id )
              iv_title = |待审批：{ lv_display }|
              iv_message = |{ lv_title }（审批步骤 { <ls_appr>-step_no }）|
              iv_link_page = '#/approvals'
              iv_severity = gc_severity_info
              iv_dedup_key = |APPR:{ <ls_appr>-appr_id }|
              iv_source = gc_source_scan
            RECEIVING
              rs_result      = ls_created.
          IF ls_created-created = abap_true.
            rs_result-approval_created = rs_result-approval_created + 1.
          ENDIF.
        CATCH zcx_crw_error.
          CONTINUE.
      ENDTRY.
    ENDLOOP.

*   Notify the assignee of every overdue task.
    SELECT * FROM zcrw_task
      WHERE assignee <> ''
        AND due_date < @lv_today
        AND due_date <> '00000000'
        AND status <> 'DONE'
        AND status <> 'CANCELLED'
      INTO TABLE @lt_task UP TO @gc_max_scan_rows ROWS.
    LOOP AT lt_task ASSIGNING FIELD-SYMBOL(<ls_task>).
      TRY.
          CALL METHOD zcl_crw_notify=>emit
            EXPORTING
              iv_user = CONV string( <ls_task>-assignee )
              iv_type = gc_type_task_overdue
              iv_object_type = 'TASK'
              iv_object_id = CONV string( <ls_task>-task_id )
              iv_title = |任务逾期：{ object_display_id( iv_object_type = 'TASK'
              iv_object_id = CONV string( <ls_task>-task_id ) ) }|
              iv_message = |{ <ls_task>-title }（截止 { <ls_task>-due_date }）|
              iv_link_page = '#/tasks'
              iv_severity = gc_severity_warn
              iv_dedup_key = |TASK_OVERDUE:{ <ls_task>-task_id }:{ <ls_task>-due_date }|
              iv_source = gc_source_scan
            RECEIVING
              rs_result      = ls_created.
          IF ls_created-created = abap_true.
            rs_result-task_created = rs_result-task_created + 1.
          ENDIF.
        CATCH zcx_crw_error.
          CONTINUE.
      ENDTRY.
    ENDLOOP.

*   Overdue schedules notify change managers and administrators.
    SELECT * FROM zcrw_sched
      WHERE status = 'PLANNED' AND scheduled_at < @lv_now AND scheduled_at <> ''
      INTO TABLE @lt_sched UP TO @gc_max_scan_rows ROWS.
    IF lt_sched IS NOT INITIAL.
      lt_scan_roles = VALUE #( ( zcl_crw_auth=>gc_change_manager ) ( zcl_crw_auth=>gc_admin ) ).
      LOOP AT lt_scan_roles ASSIGNING FIELD-SYMBOL(<lv_role>).
        APPEND LINES OF zcl_crw_auth=>role_members( iv_role = CONV string( <lv_role> ) ) TO lt_users.
      ENDLOOP.
      SORT lt_users.
      DELETE ADJACENT DUPLICATES FROM lt_users.
      LOOP AT lt_users ASSIGNING FIELD-SYMBOL(<lv_user>).
        LOOP AT lt_sched ASSIGNING FIELD-SYMBOL(<ls_sched>).
          TRY.
              CALL METHOD zcl_crw_notify=>emit
                EXPORTING
                  iv_user = <lv_user>
                  iv_type = gc_type_sched_overdue
                  iv_object_type = 'SCHED'
                  iv_object_id = CONV string( <ls_sched>-sched_id )
                  iv_title = |导入计划逾期：{ <ls_sched>-object_id }|
                  iv_message = |计划于 { <ls_sched>-scheduled_at } 导入 { <ls_sched>-target_sys }，尚未确认|
                  iv_link_page = '#/schedule'
                  iv_severity = gc_severity_warn
                  iv_dedup_key = |SCHED_OVERDUE:{ <ls_sched>-sched_id }:{ <ls_sched>-scheduled_at }|
                  iv_source = gc_source_scan
                RECEIVING
                  rs_result      = ls_created.
              IF ls_created-created = abap_true.
                rs_result-schedule_created = rs_result-schedule_created + 1.
              ENDIF.
            CATCH zcx_crw_error.
              CONTINUE.
          ENDTRY.
        ENDLOOP.
      ENDLOOP.
    ENDIF.

    rs_result-total_created = rs_result-approval_created + rs_result-task_created + rs_result-schedule_created.
  ENDMETHOD.

  METHOD list_for_user.
    DATA lv_user TYPE zcrw_notify-user_id.
    DATA lv_status TYPE string.
    DATA lv_type TYPE string.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_offset TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE tt_notifications.
    DATA lt_filtered TYPE tt_notifications.

    lv_user = iv_user.
    lv_status = to_upper( iv_status ).
    lv_type = to_upper( iv_type ).
    lv_page = iv_page.
    IF lv_page < 1.
      lv_page = 1.
    ENDIF.
    lv_size = iv_page_size.
    IF lv_size < 1 OR lv_size > 100.
      lv_size = 20.
    ENDIF.

*   Status is the only database-side filter; type filtering is applied in memory.
    IF lv_status = gc_status_unread OR lv_status = gc_status_read OR lv_status = gc_status_dismissed.
      SELECT * FROM zcrw_notify
        WHERE user_id = @lv_user AND status = @lv_status
        INTO TABLE @lt_rows.
    ELSE.
      SELECT * FROM zcrw_notify
        WHERE user_id = @lv_user
        INTO TABLE @lt_rows.
    ENDIF.
    SORT lt_rows BY created_at DESCENDING notify_id DESCENDING.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      IF lv_type IS NOT INITIAL AND <ls_row>-notify_type <> lv_type.
        CONTINUE.
      ENDIF.
      APPEND <ls_row> TO lt_filtered.
    ENDLOOP.

    rs_result-total = lines( lt_filtered ).

*   Slice the current page in memory; the v1 tables stay small.
    lv_offset = ( lv_page - 1 ) * lv_size.
    lv_from = lv_offset + 1.
    lv_to = lv_offset + lv_size.
    LOOP AT lt_filtered ASSIGNING <ls_row> FROM lv_from TO lv_to.
      APPEND <ls_row> TO rs_result-items.
    ENDLOOP.
  ENDMETHOD.

  METHOD unread_count.
    DATA lv_user TYPE zcrw_notify-user_id.

    lv_user = iv_user.
    SELECT COUNT(*) FROM zcrw_notify
      WHERE user_id = @lv_user AND status = @gc_status_unread
      INTO @rv_count.
  ENDMETHOD.

  METHOD mark_read.
    DATA lv_user TYPE zcrw_notify-user_id.
    DATA lv_id TYPE zcrw_notify-notify_id.
    DATA lv_now TYPE char14.

    IF iv_notify_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Notification id is required'.
    ENDIF.

    lv_user = iv_user.
    lv_id = iv_notify_id.
    lv_now = zcl_crw_util=>now( ).

    SELECT SINGLE notify_id FROM zcrw_notify
      WHERE notify_id = @lv_id AND user_id = @lv_user
      INTO @DATA(lv_exists).
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOTIFY_NOT_FOUND' iv_text = |Notification { iv_notify_id } not found|.
    ENDIF.

    UPDATE zcrw_notify
      SET status = @gc_status_read, read_at = @lv_now
      WHERE notify_id = @lv_id AND user_id = @lv_user AND status = @gc_status_unread.
    rv_updated = sy-dbcnt.
  ENDMETHOD.

  METHOD mark_all_read.
    DATA lv_user TYPE zcrw_notify-user_id.
    DATA lv_now TYPE char14.

    lv_user = iv_user.
    lv_now = zcl_crw_util=>now( ).

    UPDATE zcrw_notify
      SET status = @gc_status_read, read_at = @lv_now
      WHERE user_id = @lv_user AND status = @gc_status_unread.
    rv_updated = sy-dbcnt.
  ENDMETHOD.

  METHOD notify_approval_pending.
    DATA ls_created TYPE ty_create_result.

    IF is_step-appr_id IS INITIAL OR is_step-approver IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        DATA(lv_display) = object_display_id( iv_object_type = CONV string( is_step-object_type )
                                             iv_object_id   = CONV string( is_step-object_id ) ).
        DATA(lv_title) = object_title( iv_object_type = CONV string( is_step-object_type )
                                       iv_object_id   = CONV string( is_step-object_id ) ).
        CALL METHOD zcl_crw_notify=>emit
          EXPORTING
            iv_user = CONV string( is_step-approver )
            iv_type = gc_type_approval_pending
            iv_object_type = CONV string( is_step-object_type )
            iv_object_id = CONV string( is_step-object_id )
            iv_title = |待审批：{ lv_display }|
            iv_message = |{ lv_title }（审批步骤 { is_step-step_no }）|
            iv_link_page = '#/approvals'
            iv_severity = gc_severity_info
            iv_dedup_key = |APPR:{ is_step-appr_id }|
            iv_source = gc_source_event
          RECEIVING
            rs_result      = ls_created.
      CATCH zcx_crw_error.
*       Notification failures must never block the approval flow.
        RETURN.
    ENDTRY.
  ENDMETHOD.

  METHOD notify_approval_rejected.
    DATA lv_requester TYPE string.
    DATA ls_created TYPE ty_create_result.

    lv_requester = object_requester( iv_object_type = iv_object_type
                                     iv_object_id   = iv_object_id ).
    IF lv_requester IS INITIAL.
      RETURN.
    ENDIF.

    TRY.
        DATA(lv_display) = object_display_id( iv_object_type = iv_object_type iv_object_id = iv_object_id ).
        CALL METHOD zcl_crw_notify=>emit
          EXPORTING
            iv_user = lv_requester
            iv_type = gc_type_approval_rejected
            iv_object_type = iv_object_type
            iv_object_id = iv_object_id
            iv_title = |审批被驳回：{ lv_display }|
            iv_message = |审批意见：{ iv_comment }|
            iv_link_page = object_link( iv_object_type = iv_object_type iv_object_id = iv_object_id )
            iv_severity = gc_severity_warn
            iv_dedup_key = |REJ:{ iv_object_type }:{ iv_object_id }:{ iv_appr_id }|
            iv_source = gc_source_event
          RECEIVING
            rs_result      = ls_created.
      CATCH zcx_crw_error.
*       Notification failures must never block the rejection flow.
        RETURN.
    ENDTRY.
  ENDMETHOD.

  METHOD type_is_valid.
    rv_valid = xsdbool( iv_type = gc_type_approval_pending
                        OR iv_type = gc_type_approval_rejected
                        OR iv_type = gc_type_task_overdue
                        OR iv_type = gc_type_sched_overdue
                        OR iv_type = gc_type_info ).
  ENDMETHOD.

  METHOD notification_exists.
    DATA lv_user TYPE zcrw_notify-user_id.
    DATA lv_dedup TYPE zcrw_notify-dedup_key.

    lv_user = iv_user.
    lv_dedup = iv_dedup_key.
    SELECT SINGLE notify_id FROM zcrw_notify
      WHERE user_id = @lv_user AND dedup_key = @lv_dedup
      INTO @DATA(lv_id).
    rv_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD object_display_id.
    CASE iv_object_type.
      WHEN 'REQ'.
        rv_id = |CR-{ iv_object_id }|.
      WHEN 'CD'.
        rv_id = |CD-{ iv_object_id }|.
      WHEN 'TASK'.
        SELECT SINGLE task_level FROM zcrw_task WHERE task_id = @iv_object_id INTO @DATA(lv_level).
        rv_id = COND #( WHEN lv_level = 'S' THEN |ST-{ iv_object_id }| ELSE |T-{ iv_object_id }| ).
      WHEN 'SCHED'.
        SELECT SINGLE object_type, object_id FROM zcrw_sched
          WHERE sched_id = @iv_object_id INTO @DATA(ls_sched).
        IF sy-subrc = 0 AND ls_sched-object_type = 'CD'.
          rv_id = |CD-{ ls_sched-object_id }|.
        ELSE.
          rv_id = iv_object_id.
        ENDIF.
      WHEN OTHERS.
        rv_id = iv_object_id.
    ENDCASE.
  ENDMETHOD.

  METHOD object_title.
    CASE iv_object_type.
      WHEN 'REQ'.
        SELECT SINGLE title FROM zcrw_req WHERE req_id = @iv_object_id INTO @rv_title.
      WHEN 'CD'.
        SELECT SINGLE title FROM zcrw_cd WHERE cd_id = @iv_object_id INTO @rv_title.
      WHEN 'TASK'.
        SELECT SINGLE title FROM zcrw_task WHERE task_id = @iv_object_id INTO @rv_title.
      WHEN 'SCHED'.
        SELECT SINGLE object_type, object_id FROM zcrw_sched
          WHERE sched_id = @iv_object_id INTO @DATA(ls_sched).
        IF sy-subrc = 0 AND ls_sched-object_type = 'CD'.
          SELECT SINGLE title FROM zcrw_cd WHERE cd_id = @ls_sched-object_id INTO @rv_title.
        ENDIF.
      WHEN OTHERS.
        CLEAR rv_title.
    ENDCASE.
  ENDMETHOD.

  METHOD object_requester.
    DATA lv_req_id TYPE zcrw_cd-req_id.

    CASE iv_object_type.
      WHEN 'REQ'.
        SELECT SINGLE requester FROM zcrw_req WHERE req_id = @iv_object_id INTO @rv_user.
      WHEN 'CD'.
        SELECT SINGLE req_id FROM zcrw_cd WHERE cd_id = @iv_object_id INTO @lv_req_id.
        SELECT SINGLE requester FROM zcrw_req WHERE req_id = @lv_req_id INTO @rv_user.
    ENDCASE.
  ENDMETHOD.

  METHOD object_link.
    CASE iv_object_type.
      WHEN 'REQ'.
        rv_link = |#/requests/{ iv_object_id }|.
      WHEN 'CD'.
        rv_link = |#/change-documents/{ iv_object_id }|.
      WHEN 'TASK'.
        rv_link = '#/tasks'.
      WHEN 'SCHED'.
        rv_link = '#/schedule'.
      WHEN OTHERS.
        CLEAR rv_link.
    ENDCASE.
  ENDMETHOD.

  METHOD user_has_scan_role.
    DATA lt_roles TYPE zcl_crw_auth=>tt_roles.
    DATA lt_scan_roles TYPE string_table.

    lt_roles = zcl_crw_auth=>load_roles( iv_user = iv_user ).
    lt_scan_roles = VALUE #( ( zcl_crw_auth=>gc_change_manager ) ( zcl_crw_auth=>gc_admin ) ).
    rv_has = zcl_crw_auth=>has_any_role( it_roles = lt_roles iv_roles = lt_scan_roles ).
  ENDMETHOD.

  METHOD deliver_email.
*   Reserved external channel. SMTP is not configured in the current
*   environment (SCOT pending), so v1.2 only stores the in-app notification.
*   Replace this body with a BCS send once basis enables SMTP.
    rv_sent = abap_false.
  ENDMETHOD.

  METHOD truncate.
    rv_text = iv_text.
    IF strlen( rv_text ) > iv_length.
      rv_text = substring( val = rv_text len = iv_length ).
    ENDIF.
  ENDMETHOD.

  METHOD if_oo_adt_classrun~main.
    DATA lv_rows TYPE i.
    DATA lv_unread TYPE i.

    SELECT COUNT(*) FROM zcrw_notify INTO @lv_rows.
    SELECT COUNT(*) FROM zcrw_notify WHERE status = @gc_status_unread INTO @lv_unread.

    out->write( |CRW_NOTIFY_OK rows={ lv_rows } unread={ lv_unread }| ).
  ENDMETHOD.
ENDCLASS.
