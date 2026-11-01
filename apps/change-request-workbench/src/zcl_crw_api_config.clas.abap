CLASS zcl_crw_api_config DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS dispatch
      IMPORTING io_ctx      TYPE REF TO zcl_crw_api_context
                it_segments TYPE string_table
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    TYPES: BEGIN OF ty_number_range,
             object  TYPE string,
             range   TYPE string,
             from_no TYPE string,
             to_no   TYPE string,
             current TYPE string,
           END OF ty_number_range.
    TYPES tt_number_ranges TYPE STANDARD TABLE OF ty_number_range WITH EMPTY KEY.

    CLASS-METHODS list_cycles
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context.

    CLASS-METHODS list_roles
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context.

    CLASS-METHODS list_matrix
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context.

    CLASS-METHODS list_number_ranges
      IMPORTING io_ctx TYPE REF TO zcl_crw_api_context.
ENDCLASS.

CLASS zcl_crw_api_config IMPLEMENTATION.
  METHOD dispatch.
    DATA lv_kind TYPE string.

    IF lines( it_segments ) < 2.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'NOT_FOUND' iv_text = 'Unknown config path'.
    ENDIF.

    IF io_ctx->mv_method <> 'GET'.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING iv_code = 'VALIDATION_ERROR' iv_text = 'Configuration is read-only in v1'.
    ENDIF.

    lv_kind = it_segments[ 2 ].

    CASE lv_kind.
      WHEN 'cycles'.
        list_cycles( io_ctx ).
      WHEN 'roles'.
        list_roles( io_ctx ).
      WHEN 'approval-matrix'.
        list_matrix( io_ctx ).
      WHEN 'number-ranges'.
        list_number_ranges( io_ctx ).
      WHEN OTHERS.
        RAISE EXCEPTION TYPE zcx_crw_error
          EXPORTING iv_code = 'NOT_FOUND' iv_text = |Unknown configuration { lv_kind }|.
    ENDCASE.
  ENDMETHOD.

  METHOD list_cycles.
    DATA lt_rows TYPE STANDARD TABLE OF zcrw_cycle WITH EMPTY KEY.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_cycles.

    SELECT * FROM zcrw_cycle INTO TABLE @lt_rows ORDER BY cycle_id ASCENDING.
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      APPEND zcl_crw_api_map=>cycle( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_data( lt_dto ).
  ENDMETHOD.

  METHOD list_roles.
    DATA lt_rows TYPE STANDARD TABLE OF zcrw_role WITH EMPTY KEY.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_role_rows.

    SELECT * FROM zcrw_role INTO TABLE @lt_rows ORDER BY user_id ASCENDING, role ASCENDING.
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      APPEND zcl_crw_api_map=>role_row( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_data( lt_dto ).
  ENDMETHOD.

  METHOD list_matrix.
    DATA lt_rows TYPE STANDARD TABLE OF zcrw_appr_cfg WITH EMPTY KEY.
    DATA lt_dto TYPE zcl_crw_api_types=>tt_matrix_rows.

    SELECT * FROM zcrw_appr_cfg INTO TABLE @lt_rows
      ORDER BY object_type ASCENDING, profile_id ASCENDING, step_no ASCENDING.
    LOOP AT lt_rows ASSIGNING FIELD-SYMBOL(<ls_row>).
      APPEND zcl_crw_api_map=>matrix_row( <ls_row> ) TO lt_dto.
    ENDLOOP.

    io_ctx->set_data( lt_dto ).
  ENDMETHOD.

  METHOD list_number_ranges.
    DATA lt_rows TYPE tt_number_ranges.

    SELECT object, nrrangenr AS range, fromnumber AS from_no, tonumber AS to_no, nrlevel AS current
      FROM nriv
      WHERE object LIKE 'ZCRW_%'
      INTO TABLE @lt_rows.

    SORT lt_rows BY object ASCENDING.

    io_ctx->set_data( lt_rows ).
  ENDMETHOD.
ENDCLASS.
