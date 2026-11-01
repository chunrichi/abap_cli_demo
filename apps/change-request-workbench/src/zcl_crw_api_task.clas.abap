CLASS zcl_crw_api_task DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_body,
             title       TYPE string,
             assignee    TYPE string,
             due_date    TYPE string,
             est_hours   TYPE i,
             version     TYPE i,
             action      TYPE string,
             comment     TYPE string,
             task_type   TYPE string,
             cd_id       TYPE string,
             req_id      TYPE string,
           END OF ty_body.

    CONSTANTS: gc_sort_created TYPE string VALUE 'created_at',
               gc_sort_changed TYPE string VALUE 'changed_at',
               gc_sort_id      TYPE string VALUE 'task_id',
               gc_sort_title   TYPE string VALUE 'title',
               gc_sort_status  TYPE string VALUE 'status',
               gc_sort_due     TYPE string VALUE 'due_date'.

    CLASS-METHODS list_tasks
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS get_task
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_task_id TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.

    CLASS-METHODS patch_task
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_task_id TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.

    CLASS-METHODS action_task
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_task_id TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.

    CLASS-METHODS list_subtasks
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_task_id TYPE zcrw_task-task_id
      RAISING   zcx_crw_error.

    CLASS-METHODS create_subtask
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_task_id TYPE zcrw_task-task_id
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
                is_dto     TYPE zcl_crw_api_types=>ty_task
                it_subtasks TYPE zcl_crw_api_types=>tt_tasks
                it_actions TYPE string_table.
ENDCLASS.

CLASS zcl_crw_api_task IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_resource TYPE string.
    DATA lv_id TYPE string.
    DATA lv_sub TYPE string.

    IF lines( it_segments ) < 1.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown API path'.
    ENDIF.

    lv_resource = it_segments[ 1 ].
    IF lv_resource <> 'tasks'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown resource { lv_resource }|.
    ENDIF.

    IF lines( it_segments ) = 1.
      IF io_ctx->mv_method <> 'GET'.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for /tasks'.
      ENDIF.
      list_tasks( io_ctx ).
      RETURN.
    ENDIF.

    lv_id = it_segments[ 2 ].

    IF lines( it_segments ) = 2.
      CASE io_ctx->mv_method.
        WHEN 'GET'.
          get_task( io_ctx = io_ctx iv_task_id = CONV zcrw_task-task_id( lv_id ) ).
        WHEN 'PATCH'.
          patch_task( io_ctx = io_ctx iv_task_id = CONV zcrw_task-task_id( lv_id ) ).
        WHEN OTHERS.
          RAISE EXCEPTION TYPE zcx_crw_error
            EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for /tasks/{id}'.
      ENDCASE.
      RETURN.
    ENDIF.

    lv_sub = it_segments[ 3 ].
    CASE lv_sub.
      WHEN 'actions'.
        action_task( io_ctx = io_ctx iv_task_id = CONV zcrw_task-task_id( lv_id ) ).
      WHEN 'subtasks'.
        CASE io_ctx->mv_method.
          WHEN 'GET'.
            list_subtasks( io_ctx = io_ctx iv_task_id = CONV zcrw_task-task_id( lv_id ) ).
          WHEN 'POST'.
            create_subtask( io_ctx = io_ctx iv_task_id = CONV zcrw_task-task_id( lv_id ) ).
          WHEN OTHERS.
            RAISE EXCEPTION TYPE zcx_crw_error
              EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Method not allowed for subtasks'.
        ENDCASE.
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown sub resource { lv_sub }|.
    ENDCASE.
  ENDMETHOD.

  METHOD list_tasks.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_sort TYPE string.
    DATA lv_order TYPE string.
    DATA lv_field TYPE string.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lv_due_from TYPE dats.
    DATA lv_due_to TYPE dats.
    DATA lt_rows TYPE zcl_crw_task_svc=>tt_tasks.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_tasks.

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

    lv_due_from = zcl_crw_json=>parse_date( io_ctx->param( 'dueDateFrom' ) ).
    lv_due_to = zcl_crw_json=>parse_date( io_ctx->param( 'dueDateTo' ) ).

    lt_rows = zcl_crw_task_svc=>list( iv_cd_id          = CONV zcrw_task-cd_id( io_ctx->param( 'cdId' ) )
                                     iv_req_id         = CONV zcrw_task-req_id( io_ctx->param( 'reqId' ) )
                                     iv_status         = CONV zcrw_task-status( io_ctx->param( 'status' ) )
                                     iv_assignee       = CONV zcrw_task-assignee( io_ctx->param( 'assignee' ) )
                                     iv_task_type      = CONV zcrw_task-task_type( io_ctx->param( 'taskType' ) )
                                     iv_parent_task_id = CONV zcrw_task-parent_task_id( io_ctx->param( 'parentTaskId' ) )
                                     iv_due_from       = lv_due_from
                                     iv_due_to         = lv_due_to
                                     iv_query          = io_ctx->param( 'q' ) ).

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
      APPEND zcl_crw_api_map=>task( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD get_task.
    DATA ls_row TYPE zcrw_task.
    DATA ls_dto TYPE zcl_crw_api_types=>ty_task.
    DATA lt_sub_rows TYPE zcl_crw_task_svc=>tt_tasks.
    DATA lt_sub_dto TYPE zcl_crw_api_types=>tt_tasks.
    DATA lt_actions TYPE string_table.

    ls_row = zcl_crw_task_svc=>get( iv_task_id ).
    ls_dto = zcl_crw_api_map=>task( ls_row ).

    lt_sub_rows = zcl_crw_task_svc=>list( iv_parent_task_id = iv_task_id ).
    LOOP AT lt_sub_rows ASSIGNING FIELD-SYMBOL(<ls_sub>).
      APPEND zcl_crw_api_map=>task( <ls_sub> ) TO lt_sub_dto.
    ENDLOOP.

    lt_actions = zcl_crw_workflow=>allowed_actions( iv_object_type = zcl_crw_workflow=>gc_obj_task
                                                    iv_status      = CONV string( ls_row-status ) ).

    detail_json( io_ctx = io_ctx is_dto = ls_dto it_subtasks = lt_sub_dto it_actions = lt_actions ).
  ENDMETHOD.

  METHOD patch_task.
    DATA ls_body TYPE ty_body.
    DATA ls_current TYPE zcrw_task.
    DATA ls_update TYPE zcrw_task.

    ls_body = read_body( io_ctx ).
    IF ls_body-version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'version is required'.
    ENDIF.

    ls_current = zcl_crw_task_svc=>get( iv_task_id ).
    ls_update = ls_current.
    ls_update-version = ls_body-version.

    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'title' ).
      validate_text( ls_body-title ).
      ls_update-title = ls_body-title.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'assignee' ).
      ls_update-assignee = ls_body-assignee.
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'dueDate' ).
      ls_update-due_date = zcl_crw_json=>parse_date( ls_body-due_date ).
    ENDIF.
    IF zcl_crw_json=>has_key( iv_json = io_ctx->mv_body iv_key = 'estHours' ).
      ls_update-est_hours = CONV zcrw_task-est_hours( ls_body-est_hours ).
    ENDIF.

    zcl_crw_task_svc=>update( ls_update ).
    io_ctx->set_data( zcl_crw_api_map=>task( zcl_crw_task_svc=>get( iv_task_id ) ) ).
  ENDMETHOD.

  METHOD action_task.
    DATA ls_body TYPE ty_body.

    ls_body = read_body( io_ctx ).
    IF ls_body-action IS INITIAL OR ls_body-version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'action and version are required'.
    ENDIF.

    zcl_crw_task_svc=>action( iv_task_id = iv_task_id
                              iv_action  = to_upper( ls_body-action )
                              iv_version = ls_body-version
                              iv_comment = ls_body-comment ).

    io_ctx->set_data( zcl_crw_api_map=>task( zcl_crw_task_svc=>get( iv_task_id ) ) ).
  ENDMETHOD.

  METHOD list_subtasks.
    DATA lv_page TYPE i.
    DATA lv_size TYPE i.
    DATA lv_total TYPE i.
    DATA lv_count TYPE i.
    DATA lv_from TYPE i.
    DATA lv_to TYPE i.
    DATA lt_rows TYPE zcl_crw_task_svc=>tt_tasks.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_tasks.

    page_params( EXPORTING io_ctx = io_ctx IMPORTING ev_page = lv_page ev_size = lv_size ).
    lt_rows = zcl_crw_task_svc=>list( iv_parent_task_id = iv_task_id ).

    lv_total = lines( lt_rows ).
    lv_count = slice_count( iv_total = lv_total iv_page = lv_page iv_size = lv_size ).
    lv_from = ( lv_page - 1 ) * lv_size + 1.
    lv_to = lv_from + lv_count - 1.

    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>) FROM lv_from TO lv_to.
      APPEND zcl_crw_api_map=>task( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_paged( it_items = lt_dto iv_page = lv_page iv_page_size = lv_size iv_total = lv_total ).
  ENDMETHOD.

  METHOD create_subtask.
    DATA ls_body TYPE ty_body.
    DATA ls_parent TYPE zcrw_task.
    DATA ls_input TYPE zcl_crw_task_svc=>ty_create_input.

    ls_body = read_body( io_ctx ).
    validate_text( ls_body-title ).

    ls_parent = zcl_crw_task_svc=>get( iv_task_id ).
    ls_input-req_id = ls_parent-req_id.
    ls_input-cd_id = ls_parent-cd_id.
    ls_input-parent_task_id = iv_task_id.
    ls_input-task_type = ls_body-task_type.
    ls_input-title = ls_body-title.
    ls_input-assignee = ls_body-assignee.
    ls_input-due_date = zcl_crw_json=>parse_date( ls_body-due_date ).
    ls_input-est_hours = CONV zcrw_task-est_hours( ls_body-est_hours ).

    DATA(lv_sub_id) = zcl_crw_task_svc=>create( ls_input ).
    io_ctx->set_status( 201 ).
    io_ctx->set_data( zcl_crw_api_map=>task( zcl_crw_task_svc=>get( lv_sub_id ) ) ).
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
      WHEN 'dueDate'.
        rv_field = gc_sort_due.
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

    lv_base = zcl_crw_json=>serialize( is_dto ).
    lv_length = strlen( lv_base ).
    IF lv_length > 1.
      lv_base = substring( val = lv_base len = lv_length - 1 ).
    ENDIF.

    lv_json = lv_base
           && ',"subtasks":' && zcl_crw_json=>serialize( it_subtasks )
           && ',"allowedActions":' && zcl_crw_json=>serialize( it_actions )
           && '}'.

    io_ctx->set_json( lv_json ).
  ENDMETHOD.
ENDCLASS.
