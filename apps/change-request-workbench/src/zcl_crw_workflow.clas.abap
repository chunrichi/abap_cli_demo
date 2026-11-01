CLASS zcl_crw_workflow DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS: gc_obj_req   TYPE string VALUE 'REQ',
               gc_obj_cd    TYPE string VALUE 'CD',
               gc_obj_task  TYPE string VALUE 'TASK',
               gc_obj_tr    TYPE string VALUE 'TR',
               gc_obj_sched TYPE string VALUE 'SCHED',
               gc_obj_cfg   TYPE string VALUE 'CONFIG'.

*   Change request statuses.
    CONSTANTS: gc_req_new       TYPE string VALUE 'NEW',
               gc_req_pending   TYPE string VALUE 'PENDING_APPROVAL',
               gc_req_rejected  TYPE string VALUE 'REJECTED',
               gc_req_approved  TYPE string VALUE 'APPROVED',
               gc_req_progress  TYPE string VALUE 'IN_PROGRESS',
               gc_req_closed    TYPE string VALUE 'CLOSED',
               gc_req_cancelled TYPE string VALUE 'CANCELLED'.

*   Change document statuses.
    CONSTANTS: gc_cd_new       TYPE string VALUE 'NEW',
               gc_cd_dev       TYPE string VALUE 'IN_DEV',
               gc_cd_test      TYPE string VALUE 'IN_TEST',
               gc_cd_ready     TYPE string VALUE 'READY_TO_IMPORT',
               gc_cd_scheduled TYPE string VALUE 'IMPORT_SCHEDULED',
               gc_cd_imported  TYPE string VALUE 'IMPORTED',
               gc_cd_closed    TYPE string VALUE 'CLOSED',
               gc_cd_cancelled TYPE string VALUE 'CANCELLED'.

*   Task statuses.
    CONSTANTS: gc_task_open     TYPE string VALUE 'OPEN',
               gc_task_progress TYPE string VALUE 'IN_PROGRESS',
               gc_task_done     TYPE string VALUE 'DONE',
               gc_task_cancelled TYPE string VALUE 'CANCELLED'.

*   Actions.
    CONSTANTS: gc_act_submit          TYPE string VALUE 'SUBMIT',
               gc_act_withdraw        TYPE string VALUE 'WITHDRAW',
               gc_act_approve_step    TYPE string VALUE 'APPROVE_STEP',
               gc_act_skip_step       TYPE string VALUE 'SKIP_STEP',
               gc_act_reject          TYPE string VALUE 'REJECT',
               gc_act_revise          TYPE string VALUE 'REVISE',
               gc_act_start_progress  TYPE string VALUE 'START_PROGRESS',
               gc_act_close           TYPE string VALUE 'CLOSE',
               gc_act_cancel          TYPE string VALUE 'CANCEL',
               gc_act_start_dev       TYPE string VALUE 'START_DEV',
               gc_act_submit_test     TYPE string VALUE 'SUBMIT_TEST',
               gc_act_pass_test       TYPE string VALUE 'PASS_TEST',
               gc_act_submit_approval TYPE string VALUE 'SUBMIT_APPROVAL',
               gc_act_mark_ready      TYPE string VALUE 'MARK_READY',
               gc_act_schedule_import TYPE string VALUE 'SCHEDULE_IMPORT',
               gc_act_confirm_import  TYPE string VALUE 'CONFIRM_IMPORT',
               gc_act_start           TYPE string VALUE 'START',
               gc_act_done            TYPE string VALUE 'DONE'.

    CLASS-METHODS target_status
      IMPORTING iv_object_type TYPE string
                iv_from        TYPE string
                iv_action      TYPE string
      RETURNING VALUE(rv_to)   TYPE string.

    CLASS-METHODS is_terminal
      IMPORTING iv_object_type   TYPE string
                iv_status        TYPE string
      RETURNING VALUE(rv_terminal) TYPE abap_bool.

    CLASS-METHODS is_valid
      IMPORTING iv_object_type TYPE string
                iv_from        TYPE string
                iv_action      TYPE string
      RETURNING VALUE(rv_valid) TYPE abap_bool.

    CLASS-METHODS allowed_actions
      IMPORTING iv_object_type      TYPE string
                iv_status           TYPE string
      RETURNING VALUE(rt_actions)   TYPE string_table.
ENDCLASS.

CLASS zcl_crw_workflow IMPLEMENTATION.
  METHOD target_status.
    CASE iv_object_type.
      WHEN gc_obj_req.
        CASE iv_action.
          WHEN gc_act_submit.
            IF iv_from = gc_req_new.
              rv_to = gc_req_pending.
            ENDIF.
          WHEN gc_act_withdraw.
            IF iv_from = gc_req_pending.
              rv_to = gc_req_new.
            ENDIF.
          WHEN gc_act_approve_step OR gc_act_skip_step.
            IF iv_from = gc_req_pending.
              rv_to = gc_req_pending.
            ENDIF.
          WHEN gc_act_reject.
            IF iv_from = gc_req_pending.
              rv_to = gc_req_rejected.
            ENDIF.
          WHEN gc_act_revise.
            IF iv_from = gc_req_rejected.
              rv_to = gc_req_new.
            ENDIF.
          WHEN gc_act_start_progress.
            IF iv_from = gc_req_approved.
              rv_to = gc_req_progress.
            ENDIF.
          WHEN gc_act_close.
            IF iv_from = gc_req_progress.
              rv_to = gc_req_closed.
            ENDIF.
          WHEN gc_act_cancel.
            IF is_terminal( iv_object_type = gc_obj_req iv_status = iv_from ) = abap_false.
              rv_to = gc_req_cancelled.
            ENDIF.
        ENDCASE.
      WHEN gc_obj_cd.
        CASE iv_action.
          WHEN gc_act_start_dev.
            IF iv_from = gc_cd_new.
              rv_to = gc_cd_dev.
            ENDIF.
          WHEN gc_act_submit_test.
            IF iv_from = gc_cd_dev.
              rv_to = gc_cd_test.
            ENDIF.
          WHEN gc_act_pass_test OR gc_act_submit_approval.
            IF iv_from = gc_cd_test.
              rv_to = gc_cd_test.
            ENDIF.
          WHEN gc_act_mark_ready.
            IF iv_from = gc_cd_test.
              rv_to = gc_cd_ready.
            ENDIF.
          WHEN gc_act_schedule_import.
            IF iv_from = gc_cd_ready.
              rv_to = gc_cd_scheduled.
            ELSEIF iv_from = gc_cd_scheduled.
              rv_to = gc_cd_ready.
            ENDIF.
          WHEN gc_act_confirm_import.
            IF iv_from = gc_cd_ready OR iv_from = gc_cd_scheduled.
              rv_to = gc_cd_imported.
            ENDIF.
          WHEN gc_act_close.
            IF iv_from = gc_cd_imported.
              rv_to = gc_cd_closed.
            ENDIF.
          WHEN gc_act_cancel.
            IF is_terminal( iv_object_type = gc_obj_cd iv_status = iv_from ) = abap_false.
              rv_to = gc_cd_cancelled.
            ENDIF.
        ENDCASE.
      WHEN gc_obj_task.
        CASE iv_action.
          WHEN gc_act_start.
            IF iv_from = gc_task_open.
              rv_to = gc_task_progress.
            ENDIF.
          WHEN gc_act_done.
            IF iv_from = gc_task_progress.
              rv_to = gc_task_done.
            ENDIF.
          WHEN gc_act_cancel.
            IF is_terminal( iv_object_type = gc_obj_task iv_status = iv_from ) = abap_false.
              rv_to = gc_task_cancelled.
            ENDIF.
        ENDCASE.
    ENDCASE.
  ENDMETHOD.

  METHOD is_terminal.
    CASE iv_object_type.
      WHEN gc_obj_req.
        rv_terminal = xsdbool( iv_status = gc_req_closed OR iv_status = gc_req_cancelled ).
      WHEN gc_obj_cd.
        rv_terminal = xsdbool( iv_status = gc_cd_closed OR iv_status = gc_cd_cancelled ).
      WHEN gc_obj_task.
        rv_terminal = xsdbool( iv_status = gc_task_done OR iv_status = gc_task_cancelled ).
    ENDCASE.
  ENDMETHOD.

  METHOD is_valid.
    rv_valid = xsdbool( target_status( iv_object_type = iv_object_type
                                        iv_from        = iv_from
                                        iv_action      = iv_action ) IS NOT INITIAL ).
  ENDMETHOD.

  METHOD allowed_actions.
    DATA lt_actions TYPE string_table.

    CASE iv_object_type.
      WHEN gc_obj_req.
        lt_actions = VALUE #( ( gc_act_submit ) ( gc_act_withdraw ) ( gc_act_approve_step )
                              ( gc_act_skip_step ) ( gc_act_reject ) ( gc_act_revise )
                              ( gc_act_start_progress ) ( gc_act_close ) ( gc_act_cancel ) ).
      WHEN gc_obj_cd.
        lt_actions = VALUE #( ( gc_act_start_dev ) ( gc_act_submit_test ) ( gc_act_pass_test )
                              ( gc_act_submit_approval ) ( gc_act_mark_ready )
                              ( gc_act_schedule_import ) ( gc_act_confirm_import )
                              ( gc_act_close ) ( gc_act_cancel ) ).
      WHEN gc_obj_task.
        lt_actions = VALUE #( ( gc_act_start ) ( gc_act_done ) ( gc_act_cancel ) ).
    ENDCASE.

    LOOP AT lt_actions ASSIGNING FIELD-SYMBOL(<lv_action>).
      IF is_valid( iv_object_type = iv_object_type
                   iv_from        = iv_status
                   iv_action      = <lv_action> ) = abap_true.
        APPEND <lv_action> TO rt_actions.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.
ENDCLASS.
