CLASS zcl_crw_api_cd DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_body,
             title             TYPE string,
             cycle_id          TYPE string,
             target_system     TYPE string,
             owner             TYPE string,
             dev_lead          TYPE string,
             test_lead         TYPE string,
             planned_import_at TYPE string,
             version           TYPE i,
             action            TYPE string,
             comment           TYPE string,
             task_type         TYPE string,
             assignee          TYPE string,
             due_date          TYPE string,
             est_hours         TYPE i,
             scheduled_at      TYPE string,
             note              TYPE string,
             cancel_schedule   TYPE abap_bool,
           END OF ty_body.

    CONSTANTS: gc_sort_created TYPE string VALUE 'created_at',
               gc_sort_changed TYPE string VALUE 'changed_at',
               gc_sort_id      TYPE string VALUE 'cd_id',
               gc_sort_title   TYPE string VALUE 'title',
               gc_sort_status  TYPE string VALUE 'status'.

    CLASS-METHODS list_documents
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS get_document
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS patch_document
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS action_document
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS list_tasks
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS create_task
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS list_transports
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS get_schedule
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS post_schedule
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
                iv_cd_id TYPE zcrw_cd-cd_id
      RAISING   zcx_crw_error.

    CLASS-METHODS read_body
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RETURNING VALUE(rs_body) TYPE ty_body.

    CLASS-METHODS page_params
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      EXPORTING ev_page TYPE i
                ev_size TYPE i.

    CLASS-METHODS sort_field
      IMPORTING iv_sort         TYPE string
      RETURNING VALUE(rv_field) TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS slice_count
      IMPORTING iv_total       TYPE i
                iv_page        TYPE i
                iv_size        TYPE i
      RETURNING VALUE(rv_count) TYPE i.

    CLASS-METHODS validate_text
      IMPORTING iv_text TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS detail_json
      IMPORTING io_ctx     TYPE REF TO zcl_crw_api_context
                is_dto     TYPE zcl_crw_api_types=>ty_cd
                it_tasks   TYPE zcl_crw_api_types=>tt_tasks
                it_transports TYPE zcl_crw_api_types=>tt_transports
                is_sched   TYPE zcl_crw_api_types=>ty_schedule
                iv_has_sched TYPE abap_bool
                it_steps   TYPE zcl_crw_api_types=>tt_approvals
                it_actions TYPE string_table.
ENDCLASS.

CLASS zcl_crw_api_cd IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_resource TYPE string.
    DATA lv_id TYPE string.
    DATA lv_sub TYPE string.

    IF lines( it_segments ) < 1.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown API path'.
    ENDIF.

    lv_resource = it_segments[ 1 ].
    IF lv_resource <> 'change-documents'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown resource { lv_resource }|.
    ENDIF.

    IF lines( it_segments ) = 1.
      IF io_ctx->mv_method <> 'GET'.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for /change-documents'.
      ENDIF.
      list_documents( io_ctx ).
      RETURN.
    ENDIF.

    lv_id = it_segments[ 2 ].

    IF lines( it_segments ) = 2.
      CASE io_ctx->mv_method.
        WHEN 'GET'.
          get_document( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
        WHEN 'PATCH'.
          patch_document( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
        WHEN OTHERS.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for /change-documents/{id}'.
      ENDCASE.
      RETURN.
    ENDIF.

    lv_sub = it_segments[ 3 ].
    CASE lv_sub.
      WHEN 'actions'.
        action_document( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
      WHEN 'tasks'.
        CASE io_ctx->mv_method.
          WHEN 'GET'.
            list_tasks( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
          WHEN 'POST'.
            create_task( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_crw_error
              EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for tasks'.
        ENDCASE.
      WHEN 'transports'.
        list_transports( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
      WHEN 'schedule'.
        CASE io_ctx->mv_method.
          WHEN 'GET'.
            get_schedule( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
          WHEN 'POST'.
            post_schedule( io_ctx = io_ctx iv_cd_id = CONV zcrw_cd-cd_id( lv_id ) ).
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_crw_error
              EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for schedule'.
        ENDCASE.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown sub resource { lv_sub }|.
    ENDCASE.
  ENDMETHOD.

  METHOD list_documents.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_sort TYPE string.
    DATA lv_order TYPE string.
    DATA lv_field TYPE string.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE zcl_crw_cd_svc=>tt_documents.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_cds.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).

    lv_sort = io_ctx->param( 'sort' ).
    IF lv_sort IS INITIAL.
      lv_sort = 'createdAt'.
    ENDIF.
    lv_field = sort_field( lv_sort ).

    lv_order = to_lower( io_ctx->param( 'order' ) ).
    IF lv_order <> 'asc'.
      lv_order = 'desc'.
    ENDIF.

    lt_rows = zcl_crw_cd_svc=>list( iv_req_id     = CONV zcrw_cd-req_id( io_ctx->param( 'reqId' ) )
                                     iv_status     = CONV zcrw_cd-status( io_ctx->param( 'status' ) )
                                     iv_cycle_id   = CONV zcrw_cd-cycle_id( io_ctx->param( 'cycleId' ) )
                                     iv_owner      = CONV zcrw_cd-owner( io_ctx->param( 'owner' ) )
                                     iv_target_sys = CONV zcrw_cd-target_sys( io_ctx->param( 'targetSystem' ) )
                                     iv_query      = io_ctx->param( 'q' ) ).

    IF lv_order = 'asc'.
      SORT lt_rows BY (lv_field) ASCENDING.
    ELSE.
      SORT lt_rows BY (lv_field) DESCENDING.
    ENDIF.

    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>change_document( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD get_document.
    DATA ls_row TYPE zcrw_cd.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_cd.
    DATA lt_task_rows TYPE zcl_crw_task_svc=>tt_tasks.
    DATA lt_task_dto TYPE zcl_crw_api_types=>tt_tasks.
    DATA lt_tr_rows TYPE STANDARD TABLE OF zcrw_tr WITH EMPTY KEY.
    DATA lt_tr_dto TYPE zcl_crw_api_types=>tt_transports.
    DATA lt_step_rows TYPE zcl_crw_appr_svc=>tt_approvals.
    DATA lt_step_dto TYPE zcl_crw_api_types=>tt_approvals.
    DATA ls_sched_row TYPE zcrw_sched.
    DATA ls_sched_dto TYPE zcl_crw_api_types=>ty_schedule.
    DATA lv_has_sched TYPE abap_bool.
    DATA lt_actions TYPE string_table.

    ls_row = zcl_crw_cd_svc=>get( iv_cd_id ).
    ls_dto = zcl_crw_api_map=>change_document( ls_row ).

    lt_task_rows = zcl_crw_task_svc=>list( iv_cd_id = iv_cd_id ).
    LOOP AT lt_task_rows ASSIGNING FIELD-SYMBOL(<ls_task>).
      APPEND zcl_crw_api_map=>task( <ls_task> ) TO lt_task_dto.
    ENDLOOP.

    SELECT * FROM zcrw_tr WHERE cd_id = @iv_cd_id INTO TABLE @lt_tr_rows.
    LOOP AT lt_tr_rows ASSIGNING FIELD-SYMBOL(<ls_tr>).
      APPEND zcl_crw_api_map=>transport( <ls_tr> ) TO lt_tr_dto.
    ENDLOOP.

    lt_step_rows = zcl_crw_appr_svc=>steps_for_object( iv_object_type = 'CD' iv_object_id = CONV string( iv_cd_id ) ).
    LOOP AT lt_step_rows ASSIGNING FIELD-SYMBOL(<ls_step>).
      APPEND zcl_crw_api_map=>approval( is_row        = <ls_step>
                                        iv_display_id = ls_dto-display_id
                                        iv_title      = ls_dto-title ) TO lt_step_dto.
    ENDLOOP.

    ls_sched_row = zcl_crw_schedule_svc=>active_for_object( iv_object_type = 'CD'
                                                            iv_object_id   = CONV string( iv_cd_id ) ).
    IF ls_sched_row-sched_id IS NOT INITIAL.
      lv_has_sched = abap_true.
      ls_sched_dto = zcl_crw_api_map=>import_schedule( ls_sched_row ).
    ENDIF.

    lt_actions = zcl_crw_workflow=>allowed_actions( iv_object_type = zcl_crw_workflow=>gc_obj_cd
                                                    iv_status      = CONV string( ls_row-status ) ).

    detail_json( io_ctx       = io_ctx
                 is_dto       = ls_dto
                 it_tasks     = lt_task_dto
                 it_transports = lt_tr_dto
                 is_sched     = ls_sched_dto
                 iv_has_sched = lv_has_sched
                 it_steps     = lt_step_dto
                 it_actions   = lt_actions ).
  ENDMETHOD.

  METHOD patch_document.
    DATA ls_body TYPE ty_body.
    DATA ls_current TYPE zcrw_cd.
    DATA ls_update TYPE zcrw_cd.

    ls_body = read_body( io_ctx ).
    IF ls_body-version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'version is required'.
    ENDIF.

    ls_current = zcl_crw_cd_svc=>get( iv_cd_id ).
    ls_update = ls_current.
    ls_update-version = ls_body-version.

    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'title' ).
      validate_text( ls_body-title ).
      ls_update-title = ls_body-title.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'cycleId' ).
      ls_update-cycle_id = ls_body-cycle_id.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'targetSystem' ).
      ls_update-target_sys = ls_body-target_system.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'owner' ).
      ls_update-owner = ls_body-owner.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'devLead' ).
      ls_update-dev_lead = ls_body-dev_lead.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'testLead' ).
      ls_update-test_lead = ls_body-test_lead.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'plannedImportAt' ).
      ls_update-planned_import_at = zcl_crw_json=>parse_timestamp( ls_body-planned_import_at ).
    ENDIF.

    zcl_crw_cd_svc=>update( ls_update ).
    io_ctx->set_data( zcl_crw_api_map=>change_document( zcl_crw_cd_svc=>get( iv_cd_id ) ) ).
  ENDMETHOD.

  METHOD action_document.
    DATA ls_body TYPE ty_body.

    if io_ctx->mv_method <> 'POST'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Actions require POST'.
    ENDIF.

    ls_body = read_body( io_ctx ).
    IF ls_body-action IS INITIAL OR ls_body-version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'action and version are required'.
    ENDIF.

    zcl_crw_cd_svc=>action( iv_cd_id             = iv_cd_id
                            iv_action            = to_upper( ls_body-action )
                            iv_version           = ls_body-version
                            iv_comment           = ls_body-comment
                            iv_planned_import_at = ls_body-planned_import_at
                            iv_cancel_schedule   = ls_body-cancel_schedule ).

    io_ctx->set_data( zcl_crw_api_map=>change_document( zcl_crw_cd_svc=>get( iv_cd_id ) ) ).
  ENDMETHOD.

  METHOD list_tasks.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE zcl_crw_task_svc=>tt_tasks.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_tasks.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).
    lt_rows = zcl_crw_task_svc=>list( iv_cd_id = iv_cd_id ).
    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>task( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD create_task.
    DATA ls_body TYPE ty_body.
    DATA ls_input TYPE zcl_crw_task_svc=>ty_create_input.
    DATA ls_parent TYPE zcrw_cd.

    ls_body = read_body( io_ctx ).
    validate_text( ls_body-title ).

    ls_parent = zcl_crw_cd_svc=>get( iv_cd_id ).
    ls_input-req_id = ls_parent-req_id.
    ls_input-cd_id = iv_cd_id.
    ls_input-task_type = ls_body-task_type.
    ls_input-title = ls_body-title.
    ls_input-assignee = ls_body-assignee.
    ls_input-due_date = zcl_crw_json=>parse_date( ls_body-due_date ).
    ls_input-est_hours = CONV zcrw_task-est_hours( ls_body-est_hours ).

    DATA(lv_task_id) = zcl_crw_task_svc=>create( ls_input ).
    io_ctx->set_status( 201 ).
    io_ctx->set_data( zcl_crw_api_map=>task( zcl_crw_task_svc=>get( lv_task_id ) ) ).
  ENDMETHOD.

  METHOD list_transports.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE STANDARD TABLE OF zcrw_tr WITH EMPTY KEY.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_transports.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).
    SELECT * FROM zcrw_tr WHERE cd_id = @iv_cd_id INTO TABLE @lt_rows.

    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>transport( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD get_schedule.
    DATA ls_sched TYPE zcrw_sched.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_schedule.

    ls_sched = zcl_crw_schedule_svc=>active_for_object( iv_object_type = 'CD'
                                                         iv_object_id   = CONV string( iv_cd_id ) ).
    IF ls_sched-sched_id IS INITIAL.
      io_ctx->set_json( 'null' ).
      RETURN.
    ENDIF.

    ls_dto = zcl_crw_api_map=>import_schedule( ls_sched ).
    io_ctx->set_data( ls_dto ).
  ENDMETHOD.

  METHOD post_schedule.
    DATA ls_body TYPE ty_body.
    DATA ls_cd TYPE zcrw_cd.
    DATA lv_planned TYPE char14.
    DATA ls_sched TYPE zcrw_sched.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_schedule.

    ls_body = read_body( io_ctx ).
    ls_cd = zcl_crw_cd_svc=>get( iv_cd_id ).
    lv_planned = zcl_crw_json=>parse_timestamp( ls_body-scheduled_at ).
    IF lv_planned IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'scheduledAt is required'.
    ENDIF.

    IF ls_cd-status = zcl_crw_cd_svc=>gc_status_ready AND ls_body-version > 0.
*     Entering the scheduled state goes through the state machine action.
      zcl_crw_cd_svc=>action( iv_cd_id             = iv_cd_id
                              iv_action            = zcl_crw_workflow=>gc_act_schedule_import
                              iv_version           = ls_body-version
                              iv_comment           = ls_body-note
                              iv_planned_import_at = zcl_crw_json=>format_timestamp( lv_planned ) ).
    ELSE.
*     Rescheduling an existing plan keeps the CD in IMPORT_SCHEDULED.
      zcl_crw_schedule_svc=>create_or_update( iv_object_type  = 'CD'
                                              iv_object_id    = CONV string( iv_cd_id )
                                              iv_target_sys   = CONV string( ls_cd-target_sys )
                                              iv_scheduled_at = lv_planned
                                              iv_note         = ls_body-note ).
    ENDIF.

    ls_sched = zcl_crw_schedule_svc=>active_for_object( iv_object_type = 'CD'
                                                         iv_object_id   = CONV string( iv_cd_id ) ).
    ls_dto = zcl_crw_api_map=>import_schedule( ls_sched ).
    io_ctx->set_status( 201 ).
    io_ctx->set_data( ls_dto ).
  ENDMETHOD.

  METHOD read_body.
    zcl_crw_json=>deserialize( EXPORTING iv_json = io_ctx->mv_body CHANGING cs_data = rs_body ).
  ENDMETHOD.

  METHOD page_params.
    ev_page = io_ctx->param_int( iv_name = 'page' iv_default = 1 ).
    IF ev_page < 1.
      ev_page = 1.
    ENDIF.
    ev_size = io_ctx->param_int( iv_name = 'size' iv_default = 50 ).
    IF ev_size < 1.
      ev_size = 50.
    ENDIF.
    IF ev_size > 200.
      ev_size = 200.
    ENDIF.
  ENDMETHOD.

  METHOD sort_field.
    CASE iv_sort.
      WHEN 'createdAt'.
        rv_field = gc_sort_created.
      WHEN 'changedAt'.
        rv_field = gc_sort_changed.
      WHEN 'id'.
        rv_field = gc_sort_id.
      WHEN 'title'.
        rv_field = gc_sort_title.
      WHEN 'status'.
        rv_field = gc_sort_status.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = |Unsupported sort field { iv_sort }|.
    ENDCASE.
  ENDMETHOD.

  METHOD slice_count.
    DATA lv_rest TYPE i.

    IF iv_page < 1 OR iv_size < 1.
      rv_count = 0.
      RETURN.
    ENDIF.

    lv_rest = iv_total - ( iv_page - 1 ) * iv_size.
    IF lv_rest <= 0.
      rv_count = 0.
    ELSE.
      rv_count = nmin( val1 = iv_size val2 = lv_rest ).
    ENDIF.
  ENDMETHOD.

  METHOD validate_text.
    IF strlen( iv_text ) > 255.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Text must not exceed 255 characters'.
    ENDIF.
  ENDMETHOD.

  METHOD detail_json.
    DATA lv_base TYPE string.
    DATA lv_length TYPE i.
    DATA lv_json TYPE string.
    DATA lv_sched TYPE string.

    lv_base = zcl_crw_json=>serialize( is_dto ).
    lv_length = strlen( lv_base ).
    IF lv_length > 1.
      lv_base = substring( val = lv_base len = lv_length - 1 ).
    ENDIF.

    IF iv_has_sched = abap_true.
      lv_sched = zcl_crw_json=>serialize( is_sched ).
    ELSE.
      lv_sched = 'null'.
    ENDIF.

    lv_json = lv_base
           && ',"tasks":' && zcl_crw_json=>serialize( it_tasks )
           && ',"transports":' && zcl_crw_json=>serialize( it_transports )
           && ',"schedule":' && lv_sched
           && ',"approvalSteps":' && zcl_crw_json=>serialize( it_steps )
           && ',"allowedActions":' && zcl_crw_json=>serialize( it_actions )
           && '}'.

    io_ctx->set_json( lv_json ).
  ENDMETHOD.
ENDCLASS.
