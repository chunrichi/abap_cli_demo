CLASS zcl_crw_log DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    CONSTANTS: gc_sev_info  TYPE string VALUE 'INFO',
               gc_sev_warn  TYPE string VALUE 'WARN',
               gc_sev_error TYPE string VALUE 'ERROR'.

    CLASS-METHODS write
      IMPORTING iv_area           TYPE string
                iv_severity       TYPE string DEFAULT gc_sev_error
                iv_message        TYPE string
                iv_context        TYPE string DEFAULT ''
                iv_correlation_id TYPE string DEFAULT ''.

    CLASS-METHODS write_and_commit
      IMPORTING iv_area           TYPE string
                iv_severity       TYPE string DEFAULT gc_sev_error
                iv_message        TYPE string
                iv_context        TYPE string DEFAULT ''
                iv_correlation_id TYPE string DEFAULT ''.

  PRIVATE SECTION.
    CLASS-METHODS truncate
      IMPORTING iv_text        TYPE string
                iv_length      TYPE i
      RETURNING VALUE(rv_text) TYPE string.
ENDCLASS.

CLASS zcl_crw_log IMPLEMENTATION.
  METHOD write.
    DATA ls_log TYPE zcrw_log.

    ls_log-log_id = zcl_crw_util=>uuid( ).
    IF ls_log-log_id IS INITIAL.
      RETURN.
    ENDIF.

    ls_log-timestamp      = zcl_crw_util=>now( ).
    ls_log-user_id        = sy-uname.
    ls_log-area           = truncate( iv_text = iv_area iv_length = 20 ).
    ls_log-severity       = truncate( iv_text = iv_severity iv_length = 10 ).
    ls_log-message        = truncate( iv_text = iv_message iv_length = 255 ).
    ls_log-context        = truncate( iv_text = iv_context iv_length = 255 ).
    ls_log-correlation_id = iv_correlation_id.

    INSERT zcrw_log FROM ls_log.
  ENDMETHOD.

  METHOD write_and_commit.
    write( iv_area           = iv_area
           iv_severity       = iv_severity
           iv_message        = iv_message
           iv_context        = iv_context
           iv_correlation_id = iv_correlation_id ).
    COMMIT WORK AND WAIT.
  ENDMETHOD.

  METHOD truncate.
    rv_text = iv_text.
    IF strlen( rv_text ) > iv_length.
      rv_text = substring( val = rv_text len = iv_length ).
    ENDIF.
  ENDMETHOD.
ENDCLASS.
