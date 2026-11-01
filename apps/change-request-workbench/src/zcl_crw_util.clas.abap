CLASS zcl_crw_util DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CLASS-METHODS now
      RETURNING VALUE(rv_timestamp) TYPE char14.

    CLASS-METHODS uuid
      RETURNING VALUE(rv_uuid) TYPE char32.

    CLASS-METHODS format_id
      IMPORTING iv_prefix TYPE string
                iv_number TYPE inri-nr
      RETURNING VALUE(rv_id) TYPE string.
ENDCLASS.

CLASS zcl_crw_util IMPLEMENTATION.
  METHOD now.
    rv_timestamp = |{ sy-datum }{ sy-uzeit }|.
  ENDMETHOD.

  METHOD uuid.
    TRY.
        rv_uuid = cl_system_uuid=>create_uuid_c32_static( ).
      CATCH cx_uuid_error.
        CLEAR rv_uuid.
    ENDTRY.
  ENDMETHOD.

  METHOD format_id.
    DATA lv_number TYPE string.
    DATA lv_offset TYPE i.

    lv_number = |{ iv_number }|.
    lv_offset = strlen( lv_number ) - 10.
    IF lv_offset < 0.
      lv_offset = 0.
    ENDIF.

    rv_id = |{ iv_prefix }-{ lv_number+lv_offset(10) }|.
  ENDMETHOD.
ENDCLASS.
