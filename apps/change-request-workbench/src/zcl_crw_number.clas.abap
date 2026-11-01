CLASS zcl_crw_number DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS gc_interval TYPE nrnr VALUE '01'.

    CLASS-METHODS ensure_intervals
      RETURNING VALUE(rv_created) TYPE i
      RAISING   zcx_crw_error.

    CLASS-METHODS next
      IMPORTING iv_object TYPE tnro-object
      RETURNING VALUE(rv_number) TYPE inri-nr
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    CONSTANTS: gc_obj_req  TYPE tnro-object VALUE 'ZCRW_REQ',
               gc_obj_cd   TYPE tnro-object VALUE 'ZCRW_CD',
               gc_obj_task TYPE tnro-object VALUE 'ZCRW_TASK',
               gc_from     TYPE char20 VALUE '0000000001',
               gc_to       TYPE char20 VALUE '9999999999',
               gc_year     TYPE nryear VALUE '0000',
               gc_proc_new TYPE procind VALUE 'I'.

    CLASS-METHODS interval_exists
      IMPORTING iv_object TYPE tnro-object
      RETURNING VALUE(rv_exists) TYPE abap_bool.

    CLASS-METHODS create_interval
      IMPORTING iv_object TYPE tnro-object
      RAISING   zcx_crw_error.
ENDCLASS.

CLASS zcl_crw_number IMPLEMENTATION.
  METHOD ensure_intervals.
    DATA lt_objects TYPE STANDARD TABLE OF tnro-object WITH EMPTY KEY.

    lt_objects = VALUE #( ( gc_obj_req ) ( gc_obj_cd ) ( gc_obj_task ) ).

    LOOP AT lt_objects ASSIGNING FIELD-SYMBOL(<lv_object>).
      IF interval_exists( <lv_object> ) = abap_true.
        CONTINUE.
      ENDIF.

      create_interval( <lv_object> ).
      rv_created = rv_created + 1.
    ENDLOOP.
  ENDMETHOD.

  METHOD next.
    DATA lv_returncode TYPE inri-returncode.

    CALL FUNCTION 'NUMBER_GET_NEXT'
      EXPORTING
        nr_range_nr = gc_interval
        object      = iv_object
      IMPORTING
        number      = rv_number
        returncode  = lv_returncode
      EXCEPTIONS
        interval_not_found      = 1
        object_not_found        = 2
        number_range_not_intern = 3
        OTHERS                  = 4.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'NR_GET'
          iv_text = |Number range { iv_object } / { gc_interval } is missing (subrc={ sy-subrc })|.
    ENDIF.
  ENDMETHOD.

  METHOD interval_exists.
    SELECT SINGLE nrrangenr
      FROM nriv
      WHERE object     = @iv_object
        AND subobject  = @space
        AND nrrangenr  = @gc_interval
      INTO @DATA(lv_interval).

    rv_exists = xsdbool( sy-subrc = 0 ).
  ENDMETHOD.

  METHOD create_interval.
    DATA lt_interval TYPE STANDARD TABLE OF inriv.
    DATA lt_error_iv TYPE STANDARD TABLE OF inriv.

    APPEND VALUE #( subobject  = ''
                    nrrangenr  = gc_interval
                    toyear     = gc_year
                    fromnumber = gc_from
                    tonumber   = gc_to
                    nrlevel    = 0
                    externind  = ''
                    procind    = gc_proc_new ) TO lt_interval.

    " INIT / UPDATE / CLOSE is the dialog-safe number range maintenance flow.
    CALL FUNCTION 'NUMBER_RANGE_UPDATE_INIT'
      EXPORTING
        object   = iv_object
      EXCEPTIONS
        object_not_found = 1
        OTHERS           = 2.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'NR_INIT'
          iv_text = |Number range init failed for { iv_object } (subrc={ sy-subrc })|.
    ENDIF.

    CALL FUNCTION 'NUMBER_RANGE_INTERVAL_UPDATE'
      EXPORTING
        object   = iv_object
      TABLES
        error_iv = lt_error_iv
        interval = lt_interval
      EXCEPTIONS
        object_not_found = 1
        error_occured    = 2
        warning_occured  = 3
        OTHERS           = 4.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'NR_UPDATE'
          iv_text = |Number range interval update failed for { iv_object } (subrc={ sy-subrc })|.
    ENDIF.

    CALL FUNCTION 'NUMBER_RANGE_UPDATE_CLOSE'
      EXPORTING
        object   = iv_object
        commit   = abap_true
      EXCEPTIONS
        no_changes_made        = 1
        object_not_initialized = 2
        OTHERS                 = 3.

    IF sy-subrc <> 0.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'NR_CLOSE'
          iv_text = |Number range close failed for { iv_object } (subrc={ sy-subrc })|.
    ENDIF.

    COMMIT WORK AND WAIT.
  ENDMETHOD.
ENDCLASS.
