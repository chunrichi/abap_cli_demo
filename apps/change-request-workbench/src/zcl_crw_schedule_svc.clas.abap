CLASS zcl_crw_schedule_svc DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES tt_schedules TYPE STANDARD TABLE OF zcrw_sched WITH EMPTY KEY.

    CONSTANTS: gc_status_planned   TYPE zcrw_sched-status VALUE 'PLANNED',
               gc_status_done      TYPE zcrw_sched-status VALUE 'DONE',
               gc_status_missed    TYPE zcrw_sched-status VALUE 'MISSED',
               gc_status_cancelled TYPE zcrw_sched-status VALUE 'CANCELLED',
               gc_obj_cd           TYPE string VALUE 'CD',
               gc_obj_toc          TYPE string VALUE 'TOC'.

    CLASS-METHODS create_or_update
      IMPORTING iv_object_type   TYPE string
                iv_object_id     TYPE string
                iv_target_sys    TYPE string
                iv_scheduled_at  TYPE char14
                iv_note          TYPE string DEFAULT ''
      RETURNING VALUE(rv_sched_id) TYPE zcrw_sched-sched_id
      RAISING   zcx_crw_error.

    CLASS-METHODS cancel
      IMPORTING iv_sched_id TYPE zcrw_sched-sched_id
                iv_note     TYPE string DEFAULT ''
      RAISING   zcx_crw_error.

    CLASS-METHODS confirm
      IMPORTING iv_sched_id TYPE zcrw_sched-sched_id
                iv_note     TYPE string DEFAULT ''
      RAISING   zcx_crw_error.

    CLASS-METHODS get
      IMPORTING iv_sched_id     TYPE zcrw_sched-sched_id
      RETURNING VALUE(rs_sched) TYPE zcrw_sched
      RAISING   zcx_crw_error.

    CLASS-METHODS active_for_object
      IMPORTING iv_object_type  TYPE string
                iv_object_id    TYPE string
      RETURNING VALUE(rs_sched) TYPE zcrw_sched.

    CLASS-METHODS list
      IMPORTING iv_from         TYPE dats OPTIONAL
                iv_to           TYPE dats OPTIONAL
                iv_target_sys   TYPE string OPTIONAL
                iv_status       TYPE string OPTIONAL
                iv_object_type  TYPE string OPTIONAL
      RETURNING VALUE(rt_schedules) TYPE tt_schedules.

    CLASS-METHODS is_overdue
      IMPORTING iv_scheduled_at TYPE char14
      RETURNING VALUE(rv_overdue) TYPE abap_bool.

    CLASS-METHODS cancel_for_object
      IMPORTING iv_object_type TYPE string
                iv_object_id   TYPE string
                iv_note        TYPE string DEFAULT ''.

  PRIVATE SECTION.
    CLASS-METHODS log_action
      IMPORTING iv_sched_id TYPE zcrw_sched-sched_id
                iv_action   TYPE string
                iv_field    TYPE string DEFAULT ''
                iv_old      TYPE string DEFAULT ''
                iv_new      TYPE string DEFAULT ''.
ENDCLASS.

CLASS zcl_crw_schedule_svc IMPLEMENTATION.
  METHOD create_or_update.
    DATA ls_sched TYPE zcrw_sched.
    DATA ls_existing TYPE zcrw_sched.
    DATA lv_now TYPE char14.

    IF iv_object_type IS INITIAL OR iv_object_id IS INITIAL OR iv_scheduled_at IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR'
                  iv_text = 'Object type, object id and schedule time are required'.
    ENDIF.

    IF strlen( iv_note ) > 255.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Note must not exceed 255 characters'.
    ENDIF.

    lv_now = zcl_crw_util=>now( ).

    ls_existing = active_for_object( iv_object_type = iv_object_type
                                     iv_object_id   = iv_object_id ).

    IF ls_existing-sched_id IS NOT INITIAL.
*     One active plan per object: an existing plan is rescheduled in place.
      UPDATE zcrw_sched
        SET scheduled_at = @iv_scheduled_at,
            note         = @iv_note,
            status       = @gc_status_planned,
            changed_at   = @lv_now,
            changed_by   = @sy-uname
        WHERE sched_id = @ls_existing-sched_id.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'SCHEDULE_CONFLICT' iv_text = 'Could not update the active schedule'.
      ENDIF.
      rv_sched_id = ls_existing-sched_id.
      log_action( iv_sched_id = ls_existing-sched_id
                  iv_action   = 'SCHEDULE_UPDATE'
                  iv_field    = 'SCHEDULED_AT'
                  iv_old      = CONV string( ls_existing-scheduled_at )
                  iv_new      = CONV string( iv_scheduled_at ) ).
    ELSE.
      ls_sched-sched_id     = zcl_crw_util=>uuid( ).
      ls_sched-object_type  = iv_object_type.
      ls_sched-object_id    = iv_object_id.
      ls_sched-target_sys   = iv_target_sys.
      ls_sched-scheduled_at = iv_scheduled_at.
      ls_sched-status       = gc_status_planned.
      ls_sched-note         = iv_note.
      ls_sched-created_at   = lv_now.
      ls_sched-created_by   = sy-uname.
      ls_sched-changed_at   = lv_now.
      ls_sched-changed_by   = sy-uname.

      INSERT zcrw_sched FROM ls_sched.
      IF sy-subrc <> 0.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'SCHEDULE_INSERT' iv_text = 'Could not create the import schedule'.
      ENDIF.
      rv_sched_id = ls_sched-sched_id.
      log_action( iv_sched_id = ls_sched-sched_id
                  iv_action   = 'SCHEDULE_CREATE'
                  iv_field    = 'SCHEDULED_AT'
                  iv_new      = CONV string( iv_scheduled_at ) ).
    ENDIF.

    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD cancel.
    DATA ls_sched TYPE zcrw_sched.
    DATA lv_now TYPE char14.

    ls_sched = get( iv_sched_id ).
    IF ls_sched-status = gc_status_done.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION' iv_text = 'A completed schedule cannot be cancelled'.
    ENDIF.
    IF ls_sched-status = gc_status_cancelled.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION' iv_text = 'The schedule is already cancelled'.
    ENDIF.

    lv_now = zcl_crw_util=>now( ).
    UPDATE zcrw_sched
      SET status     = @gc_status_cancelled,
          note       = @iv_note,
          changed_at = @lv_now,
          changed_by = @sy-uname
      WHERE sched_id = @iv_sched_id.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'SCHEDULE_UPDATE' iv_text = 'Could not cancel the schedule'.
    ENDIF.

    log_action( iv_sched_id = iv_sched_id
                iv_action   = 'SCHEDULE_CANCEL'
                iv_field    = 'STATUS'
                iv_old      = CONV string( ls_sched-status )
                iv_new      = CONV string( gc_status_cancelled ) ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD confirm.
    DATA ls_sched TYPE zcrw_sched.
    DATA lv_now TYPE char14.

    ls_sched = get( iv_sched_id ).
    IF ls_sched-status = gc_status_done.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION' iv_text = 'The schedule is already completed'.
    ENDIF.
    IF ls_sched-status = gc_status_cancelled.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'INVALID_TRANSITION' iv_text = 'A cancelled schedule cannot be confirmed'.
    ENDIF.

    lv_now = zcl_crw_util=>now( ).
    UPDATE zcrw_sched
      SET status     = @gc_status_done,
          note       = @iv_note,
          changed_at = @lv_now,
          changed_by = @sy-uname
      WHERE sched_id = @iv_sched_id.
    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'SCHEDULE_UPDATE' iv_text = 'Could not confirm the schedule'.
    ENDIF.

    log_action( iv_sched_id = iv_sched_id
                iv_action   = 'CONFIRM_IMPORT'
                iv_field    = 'STATUS'
                iv_old      = CONV string( ls_sched-status )
                iv_new      = CONV string( gc_status_done ) ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD get.
    SELECT SINGLE *
      FROM zcrw_sched
      WHERE sched_id = @iv_sched_id
      INTO @rs_sched.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'SCHED_NOT_FOUND' iv_text = |Import schedule { iv_sched_id } not found|.
    ENDIF.
  ENDMETHOD.

  METHOD active_for_object.
    DATA lv_planned TYPE zcrw_sched-status.
    DATA lv_missed TYPE zcrw_sched-status.

    lv_planned = gc_status_planned.
    lv_missed = gc_status_missed.

    SELECT SINGLE *
      FROM zcrw_sched
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
        AND ( status = @lv_planned OR status = @lv_missed )
      INTO @rs_sched.
  ENDMETHOD.

  METHOD list.
    DATA lv_from TYPE char14.
    DATA lv_to TYPE char14.
    DATA lv_active_planned TYPE zcrw_sched-status.
    DATA lv_active_missed TYPE zcrw_sched-status.

    SELECT *
      FROM zcrw_sched
      INTO TABLE @rt_schedules
      ORDER BY scheduled_at ASCENDING.

    IF iv_status IS NOT INITIAL.
      DELETE rt_schedules WHERE status <> iv_status.
    ENDIF.
    IF iv_target_sys IS NOT INITIAL.
      DELETE rt_schedules WHERE target_sys <> iv_target_sys.
    ENDIF.
    IF iv_object_type IS NOT INITIAL.
      DELETE rt_schedules WHERE object_type <> iv_object_type.
    ENDIF.
    IF iv_from IS NOT INITIAL.
      lv_from = |{ iv_from }000000|.
      DELETE rt_schedules WHERE scheduled_at < lv_from.
    ENDIF.
    IF iv_to IS NOT INITIAL.
      lv_to = |{ iv_to }235959|.
      DELETE rt_schedules WHERE scheduled_at > lv_to.
    ENDIF.
  ENDMETHOD.

  METHOD is_overdue.
    rv_overdue = xsdbool( iv_scheduled_at IS NOT INITIAL AND iv_scheduled_at < zcl_crw_util=>now( ) ).
  ENDMETHOD.

  METHOD cancel_for_object.
    DATA lt_sched TYPE tt_schedules.
    DATA lv_planned TYPE zcrw_sched-status.
    DATA lv_missed TYPE zcrw_sched-status.
    DATA lv_now TYPE char14.

    lv_planned = gc_status_planned.
    lv_missed = gc_status_missed.
    lv_now = zcl_crw_util=>now( ).

    SELECT *
      FROM zcrw_sched
      WHERE object_type = @iv_object_type
        AND object_id   = @iv_object_id
        AND ( status = @lv_planned OR status = @lv_missed )
      INTO TABLE @lt_sched.

    LOOP AT lt_sched ASSIGNING FIELD-SYMBOL(<ls_sched>).
      UPDATE zcrw_sched
        SET status     = @gc_status_cancelled,
            note       = @iv_note,
            changed_at = @lv_now,
            changed_by = @sy-uname
        WHERE sched_id = @<ls_sched>-sched_id.
      log_action( iv_sched_id = <ls_sched>-sched_id
                  iv_action   = 'SCHEDULE_CANCEL'
                  iv_field    = 'STATUS'
                  iv_old      = CONV string( <ls_sched>-status )
                  iv_new      = CONV string( gc_status_cancelled ) ).
    ENDLOOP.
  ENDMETHOD.

  METHOD log_action.
    TRY.
        zcl_crw_audit=>log( iv_object_type = 'SCHED'
                            iv_object_id   = CONV string( iv_sched_id )
                            iv_action      = iv_action
                            iv_field       = iv_field
                            iv_old_value   = iv_old
                            iv_new_value   = iv_new ).
      CATCH zcx_crw_error.
    ENDTRY.
  ENDMETHOD.
ENDCLASS.
