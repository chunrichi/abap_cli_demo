CLASS zcl_crw_m1_smoke DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    INTERFACES if_oo_adt_classrun.
ENDCLASS.

CLASS zcl_crw_m1_smoke IMPLEMENTATION.
  METHOD if_oo_adt_classrun~main.
    DATA ls_req_input  TYPE zcl_crw_request_svc=>ty_create_input.
    DATA ls_cd_input   TYPE zcl_crw_cd_svc=>ty_create_input.
    DATA ls_task_input TYPE zcl_crw_task_svc=>ty_create_input.
    DATA lt_tasks      TYPE zcl_crw_task_svc=>tt_tasks.
    DATA ls_cd         TYPE zcrw_cd.
    DATA ls_task       TYPE zcrw_task.
    DATA ls_subtask    TYPE zcrw_task.
    DATA lv_req_id     TYPE zcrw_req-req_id.
    DATA lv_cd_id      TYPE zcrw_cd-cd_id.
    DATA lv_task_id    TYPE zcrw_task-task_id.
    DATA lv_sub_id     TYPE zcrw_task-task_id.
    DATA lv_req_obj    TYPE zcrw_hist-object_id.
    DATA lv_cd_obj     TYPE zcrw_hist-object_id.
    DATA lv_task_obj   TYPE zcrw_hist-object_id.
    DATA lv_sub_obj    TYPE zcrw_hist-object_id.
    DATA lv_error      TYPE string.

    TRY.
        ls_req_input-req_type    = 'STD'.
        ls_req_input-title       = 'Smoke test change request'.
        ls_req_input-description = 'Created by ZCL_CRW_M1_SMOKE and removed afterwards'.
        ls_req_input-priority    = '3'.
        ls_req_input-component   = 'MM'.
        ls_req_input-requester   = sy-uname.
        ls_req_input-owner       = sy-uname.

        lv_req_id = zcl_crw_request_svc=>create( ls_req_input ).
        zcl_crw_request_svc=>change_status( iv_req_id = lv_req_id iv_status = 'PENDING_APPROVAL' ).
        zcl_crw_request_svc=>change_status( iv_req_id = lv_req_id iv_status = 'APPROVED' ).
        zcl_crw_request_svc=>change_status( iv_req_id = lv_req_id iv_status = 'IN_PROGRESS' ).

        ls_cd_input-req_id     = lv_req_id.
        ls_cd_input-title      = 'Smoke test change document'.
        ls_cd_input-target_sys = 'QAS'.
        lv_cd_id = zcl_crw_cd_svc=>create( ls_cd_input ).
        zcl_crw_cd_svc=>change_status( iv_cd_id = lv_cd_id iv_status = 'IN_DEV' ).

        ls_task_input-req_id    = lv_req_id.
        ls_task_input-cd_id     = lv_cd_id.
        ls_task_input-task_type = 'DEV'.
        ls_task_input-title     = 'Smoke test task'.
        lv_task_id = zcl_crw_task_svc=>create( ls_task_input ).
        zcl_crw_task_svc=>change_status( iv_task_id = lv_task_id iv_status = 'IN_PROGRESS' ).
        zcl_crw_task_svc=>change_status( iv_task_id = lv_task_id iv_status = 'DONE' ).

        ls_task_input-parent_task_id = lv_task_id.
        ls_task_input-req_id         = ''.
        ls_task_input-title          = 'Smoke test subtask'.
        lv_sub_id = zcl_crw_task_svc=>create( ls_task_input ).
        zcl_crw_task_svc=>change_status( iv_task_id = lv_sub_id iv_status = 'IN_PROGRESS' ).
        zcl_crw_task_svc=>change_status( iv_task_id = lv_sub_id iv_status = 'DONE' ).

        " Verify the hierarchy and the workflow side effects.
        lt_tasks = zcl_crw_task_svc=>list( iv_cd_id = lv_cd_id ).
        IF lines( lt_tasks ) <> 2.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'SMOKE_TASKS' iv_text = 'Expected two tasks'.
        ENDIF.

        ls_task = zcl_crw_task_svc=>get( lv_task_id ).
        ls_subtask = zcl_crw_task_svc=>get( lv_sub_id ).
        ls_cd = zcl_crw_cd_svc=>get( lv_cd_id ).

        IF ls_task-task_level <> 'T' OR ls_task-status <> 'DONE'.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'SMOKE_TASK' iv_text = 'Task level or status mismatch'.
        ENDIF.
        IF ls_subtask-task_level <> 'S' OR ls_subtask-parent_task_id <> lv_task_id OR ls_subtask-status <> 'DONE'.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'SMOKE_SUBTASK' iv_text = 'Subtask level, parent or status mismatch'.
        ENDIF.
        IF ls_cd-status <> 'IN_DEV'.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'SMOKE_CD' iv_text = 'Change document status mismatch'.
        ENDIF.
      CATCH zcx_crw_error INTO DATA(lx_error).
        lv_error = |{ lx_error->mv_code } { lx_error->mv_text }|.
    ENDTRY.

    " The smoke test always removes its own rows.
    IF lv_req_id IS NOT INITIAL.
      lv_req_obj = lv_req_id.
      DELETE FROM zcrw_hist WHERE object_type = 'REQ' AND object_id = @lv_req_obj.
      DELETE FROM zcrw_req WHERE req_id = @lv_req_id.
    ENDIF.
    IF lv_cd_id IS NOT INITIAL.
      lv_cd_obj = lv_cd_id.
      DELETE FROM zcrw_hist WHERE object_type = 'CD' AND object_id = @lv_cd_obj.
      DELETE FROM zcrw_cd WHERE cd_id = @lv_cd_id.
    ENDIF.
    IF lv_task_id IS NOT INITIAL.
      lv_task_obj = lv_task_id.
      DELETE FROM zcrw_hist WHERE object_type = 'TASK' AND object_id = @lv_task_obj.
      DELETE FROM zcrw_task WHERE task_id = @lv_task_id.
    ENDIF.
    IF lv_sub_id IS NOT INITIAL.
      lv_sub_obj = lv_sub_id.
      DELETE FROM zcrw_hist WHERE object_type = 'TASK' AND object_id = @lv_sub_obj.
      DELETE FROM zcrw_task WHERE task_id = @lv_sub_id.
    ENDIF.
    COMMIT WORK AND WAIT.

    IF lv_error IS INITIAL.
      out->write( |CRW_M1_SMOKE_OK req={ lv_req_id } cd={ lv_cd_id } task={ lv_task_id } sub={ lv_sub_id }| ).
    ELSE.
      out->write( |CRW_M1_SMOKE_FAIL { lv_error }| ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
