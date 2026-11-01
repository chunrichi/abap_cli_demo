CLASS zcl_crw_auth DEFINITION PUBLIC FINAL CREATE PUBLIC.
  PUBLIC SECTION.
    TYPES: BEGIN OF ty_role,
             role       TYPE zcrw_role-role,
             scope_type TYPE zcrw_role-scope_type,
             scope_id   TYPE zcrw_role-scope_id,
           END OF ty_role.
    TYPES tt_roles TYPE STANDARD TABLE OF ty_role WITH EMPTY KEY.

    CONSTANTS: gc_requester       TYPE string VALUE 'REQUESTER',
               gc_change_manager  TYPE string VALUE 'CHANGE_MANAGER',
               gc_developer       TYPE string VALUE 'DEVELOPER',
               gc_tester          TYPE string VALUE 'TESTER',
               gc_release_manager TYPE string VALUE 'RELEASE_MANAGER',
               gc_admin           TYPE string VALUE 'ADMIN',
               gc_viewer          TYPE string VALUE 'VIEWER'.

    CLASS-METHODS load_roles
      IMPORTING iv_user         TYPE string
                iv_date         TYPE dats OPTIONAL
      RETURNING VALUE(rt_roles) TYPE tt_roles.

    CLASS-METHODS role_members
      IMPORTING iv_role         TYPE string
                iv_date         TYPE dats OPTIONAL
      RETURNING VALUE(rt_users) TYPE string_table.

    CLASS-METHODS is_admin
      IMPORTING it_roles       TYPE tt_roles
      RETURNING VALUE(rv_admin) TYPE abap_bool.

    CLASS-METHODS has_role
      IMPORTING it_roles     TYPE tt_roles
                iv_role      TYPE string
      RETURNING VALUE(rv_has) TYPE abap_bool.

    CLASS-METHODS has_any_role
      IMPORTING it_roles     TYPE tt_roles
                iv_roles     TYPE string_table
      RETURNING VALUE(rv_has) TYPE abap_bool.

    CLASS-METHODS require_any
      IMPORTING it_roles  TYPE tt_roles
                iv_roles  TYPE string_table
                iv_action TYPE string
      RAISING   zcx_crw_error.

  PRIVATE SECTION.
    CLASS-METHODS role_date
      IMPORTING iv_date         TYPE dats OPTIONAL
      RETURNING VALUE(rv_date)  TYPE dats.
ENDCLASS.

CLASS zcl_crw_auth IMPLEMENTATION.
  METHOD load_roles.
    DATA lv_user TYPE zcrw_role-user_id.
    DATA lv_date TYPE dats.

    lv_user = iv_user.
    lv_date = role_date( iv_date ).

    SELECT role, scope_type, scope_id
      FROM zcrw_role
      WHERE user_id = @lv_user
        AND ( valid_from IS INITIAL OR valid_from <= @lv_date )
        AND ( valid_to   IS INITIAL OR valid_to   >= @lv_date )
      INTO TABLE @rt_roles.
  ENDMETHOD.

  METHOD role_members.
    DATA lv_date TYPE dats.
    DATA lt_users TYPE STANDARD TABLE OF zcrw_role-user_id WITH EMPTY KEY.

    lv_date = role_date( iv_date ).

    SELECT DISTINCT user_id
      FROM zcrw_role
      WHERE role = @iv_role
        AND ( valid_from IS INITIAL OR valid_from <= @lv_date )
        AND ( valid_to   IS INITIAL OR valid_to   >= @lv_date )
      INTO TABLE @lt_users.

    rt_users = VALUE #( FOR ls_user IN lt_users ( CONV string( ls_user ) ) ).
  ENDMETHOD.

  METHOD is_admin.
    rv_admin = has_role( it_roles = it_roles iv_role = gc_admin ).
  ENDMETHOD.

  METHOD has_role.
    DATA lv_role TYPE string.

    lv_role = iv_role.
    TRANSLATE lv_role TO UPPER CASE.

    LOOP AT it_roles ASSIGNING FIELD-SYMBOL(<ls_role>).
      IF <ls_role>-role = lv_role.
        rv_has = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD has_any_role.
    LOOP AT iv_roles ASSIGNING FIELD-SYMBOL(<lv_role>).
      IF has_role( it_roles = it_roles iv_role = <lv_role> ) = abap_true.
        rv_has = abap_true.
        RETURN.
      ENDIF.
    ENDLOOP.
  ENDMETHOD.

  METHOD require_any.
    IF is_admin( it_roles ) = abap_true.
      RETURN.
    ENDIF.
    IF has_any_role( it_roles = it_roles iv_roles = iv_roles ) = abap_false.
      RAISE EXCEPTION TYPE zcx_crw_error
        EXPORTING
          iv_code = 'FORBIDDEN'
          iv_text = |No authorization for action { iv_action }|.
    ENDIF.
  ENDMETHOD.

  METHOD role_date.
    IF iv_date IS INITIAL.
      rv_date = sy-datum.
    ELSE.
      rv_date = iv_date.
    ENDIF.
  ENDMETHOD.
ENDCLASS.
