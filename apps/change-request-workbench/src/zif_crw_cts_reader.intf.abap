INTERFACE zif_crw_cts_reader PUBLIC.
  TYPES: BEGIN OF ty_header,
           trkorr    TYPE e070-trkorr,
           trfunction TYPE e070-trfunction,
           trstatus  TYPE e070-trstatus,
           tarsystem TYPE e070-tarsystem,
           as4user   TYPE e070-as4user,
           as4date   TYPE e070-as4date,
           as4time   TYPE e070-as4time,
         END OF ty_header.

  TYPES: BEGIN OF ty_object,
           pgmid    TYPE e071-pgmid,
           object   TYPE e071-object,
           obj_name TYPE e071-obj_name,
         END OF ty_object.
  TYPES tt_objects TYPE STANDARD TABLE OF ty_object WITH EMPTY KEY.

  CONSTANTS: gc_state_modifiable TYPE string VALUE 'D',
             gc_state_released   TYPE string VALUE 'R',
             gc_state_imported   TYPE string VALUE 'I',
             gc_state_unknown    TYPE string VALUE 'U'.

  METHODS get_header
    IMPORTING iv_trkorr      TYPE e070-trkorr
    RETURNING VALUE(rs_header) TYPE ty_header
    RAISING   zcx_crw_error.

  METHODS get_description
    IMPORTING iv_trkorr       TYPE e070-trkorr
    RETURNING VALUE(rv_text)  TYPE string.

  METHODS get_objects
    IMPORTING iv_trkorr        TYPE e070-trkorr
    RETURNING VALUE(rt_objects) TYPE tt_objects
    RAISING   zcx_crw_error.

  METHODS get_import_state
    IMPORTING iv_trkorr        TYPE e070-trkorr
    RETURNING VALUE(rv_state)  TYPE string.
ENDINTERFACE.
