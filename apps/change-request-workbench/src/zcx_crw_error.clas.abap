CLASS zcx_crw_error DEFINITION PUBLIC INHERITING FROM cx_static_check FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    METHODS constructor
      IMPORTING iv_code TYPE string DEFAULT ''
                iv_text TYPE string DEFAULT ''.

    DATA mv_code TYPE string READ-ONLY.
    DATA mv_text TYPE string READ-ONLY.
ENDCLASS.

CLASS zcx_crw_error IMPLEMENTATION.
  METHOD constructor.
    super->constructor( ).

    mv_code = iv_code.
    mv_text = iv_text.
  ENDMETHOD.
ENDCLASS.
