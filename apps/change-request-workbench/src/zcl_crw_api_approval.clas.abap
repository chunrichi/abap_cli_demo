CLASS zcl_crw_api_approval DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_body,
             decision TYPE string,
             comment  TYPE string,
             version  TYPE i,
             approver TYPE string,
           END OF ty_body.

    CLASS-METHODS list_approvals
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS list_steps
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RAISING   zcx_crw_error.

    CLASS-METHODS decide
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_appr_id TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS reassign
      IMPORTING io_ctx    TYPE REF TO zcl_crw_api_context
                iv_appr_id TYPE string
      RAISING   zcx_crw_error.

    CLASS-METHODS map_rows
      IMPORTING it_rows      TYPE zcl_crw_appr_svc=>tt_approvals
      RETURNING VALUE(rt_dto) TYPE zcl_crw_api_types=>tt_approvals.

    CLASS-METHODS read_body
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context
      RETURNING VALUE(rs_body) TYPE ty_body.
ENDCLASS.

CLASS zcl_crw_api_approval IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_resource TYPE string.
    DATA lv_id TYPE string.
    DATA lv_sub TYPE string.

    IF lines( it_segments ) < 1.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown API path'.
    ENDIF.

    lv_resource = it_segments[ 1 ].
    IF lv_resource <> 'approvals'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown resource { lv_resource }|.
    ENDIF.

    IF lines( it_segments ) = 1.
      list_approvals( io_ctx ).
      RETURN.
    ENDIF.

    lv_id = it_segments[ 2 ].

    IF lv_id = 'steps'.
      list_steps( io_ctx ).
      RETURN.
    ENDIF.

    IF lines( it_segments ) >= 3.
      lv_sub = it_segments[ 3 ].
      IF lv_sub = 'decision'.
        decide( io_ctx = io_ctx iv_appr_id = lv_id ).
        RETURN.
      ENDIF.
      IF lv_sub = 'reassign'.
        reassign( io_ctx = io_ctx iv_appr_id = lv_id ).
        RETURN.
      ENDIF.
    ENDIF.

    RAISE EXCEPTION TYPE zcx_crw_error
      EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown approval path'.
  ENDMETHOD.

  METHOD list_approvals.
    DATA lv_scope TYPE string.
    DATA lt_rows TYPE zcl_crw_appr_svc=>tt_approvals.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_approvals.

    lv_scope = to_lower( io_ctx->param( 'scope' ) ).
    IF lv_scope IS INITIAL.
      lv_scope = 'mine'.
    ENDIF.
    IF lv_scope <> 'decided' AND lv_scope <> 'all'.
      lv_scope = 'mine'.
    ENDIF.

    lt_rows = zcl_crw_appr_svc=>list_for_user( iv_user = io_ctx->mv_user iv_scope = lv_scope ).
    lt_dto = map_rows( lt_rows ).
    io_ctx->set_data( lt_dto ).
  ENDMETHOD.

  METHOD list_steps.
    DATA lv_object_type TYPE string.
    DATA lv_object_id TYPE string.
    DATA lt_rows TYPE zcl_crw_appr_svc=>tt_approvals.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_approvals.

    lv_object_type = to_upper( io_ctx->param( 'objectType' ) ).
    lv_object_id = io_ctx->param( 'objectId' ).
    IF lv_object_type IS INITIAL OR lv_object_id IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'objectType and objectId are required'.
    ENDIF.

    lt_rows = zcl_crw_appr_svc=>steps_for_object( iv_object_type = lv_object_type iv_object_id = lv_object_id ).
    lt_dto = map_rows( lt_rows ).
    io_ctx->set_data( lt_dto ).
  ENDMETHOD.

  METHOD decide.
    DATA ls_body TYPE ty_body.
    DATA ls_step TYPE zcrw_appr.
    DATA ls_after TYPE zcrw_appr.
    DATA lv_json TYPE string.

    ls_body = read_body( io_ctx ).
    IF ls_body-decision IS INITIAL OR ls_body-version IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'decision and version are required'.
    ENDIF.

    ls_step = zcl_crw_appr_svc=>get_step( iv_appr_id ).
    zcl_crw_appr_svc=>decide( iv_appr_id  = iv_appr_id
                              iv_user     = io_ctx->mv_user
                              iv_decision = to_upper( ls_body-decision )
                              iv_comment  = ls_body-comment
                              iv_version  = ls_body-version ).

    ls_after = zcl_crw_appr_svc=>get_step( iv_appr_id ).
    lv_json = |\{"id":"{ ls_after-appr_id }","objectType":"{ ls_after-object_type }"| &&
              |,"objectId":"{ ls_after-object_id }","apprState":"{ ls_after-appr_state }"\}|.
    io_ctx->set_json( lv_json ).
  ENDMETHOD.

  METHOD reassign.
    DATA ls_body TYPE ty_body.
    DATA ls_after TYPE zcrw_appr.
    DATA lv_json TYPE string.

    ls_body = read_body( io_ctx ).
    IF ls_body-approver IS INITIAL.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'approver is required'.
    ENDIF.

    zcl_crw_appr_svc=>reassign( iv_appr_id      = iv_appr_id
                                iv_user         = io_ctx->mv_user
                                iv_new_approver = to_upper( ls_body-approver )
                                iv_comment      = ls_body-comment ).

    ls_after = zcl_crw_appr_svc=>get_step( iv_appr_id ).
    lv_json = |\{"id":"{ ls_after-appr_id }","objectType":"{ ls_after-object_type }"| &&
              |,"objectId":"{ ls_after-object_id }","approver":"{ ls_after-approver }"| &&
              |,"apprState":"{ ls_after-appr_state }"\}|.
    io_ctx->set_json( lv_json ).
  ENDMETHOD.

  METHOD map_rows.
    DATA lv_display TYPE string.
    DATA lv_title TYPE string.

    LOOP AT it_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      lv_display = zcl_crw_appr_svc=>object_display_id( iv_object_type = CONV string( <ls_row>-object_type )
                                                        iv_object_id   = CONV string( <ls_row>-object_id ) ).
      lv_title = zcl_crw_appr_svc=>object_title( iv_object_type = CONV string( <ls_row>-object_type )
                                                 iv_object_id   = CONV string( <ls_row>-object_id ) ).
      APPEND zcl_crw_api_map=>approval( is_row        = <ls_row>
                                        iv_display_id = lv_display
                                        iv_title      = lv_title ) TO rt_dto.
    ENDLOOP.
  ENDMETHOD.

  METHOD read_body.
    zcl_crw_json=>deserialize( EXPORTING iv_json = io_ctx->mv_body CHANGING cs_data = rs_body ).
  ENDMETHOD.
ENDCLASS.
