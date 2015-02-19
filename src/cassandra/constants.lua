return {
  version_codes = {
    REQUEST=0x02,
    RESPONSE=0x82
  },
  op_codes = {
    ERROR=0x00,
    STARTUP=0x01,
    READY=0x02,
    AUTHENTICATE=0x03,
    -- 0x04
    OPTIONS=0x05,
    SUPPORTED=0x06,
    QUERY=0x07,
    RESULT=0x08,
    PREPARE=0x09,
    EXECUTE=0x0A,
    REGISTER=0x0B,
    EVENT=0x0C,
    BATCH=0x0D,
    AUTH_CHALLENGE=0x0E,
    AUTH_RESPONSE=0x0F,
    AUTH_SUCCESS=0x10,
  },
  consistency = {
    ANY=0x0000,
    ONE=0x0001,
    TWO=0x0002,
    THREE=0x0003,
    QUORUM=0x0004,
    ALL=0x0005,
    LOCAL_QUORUM=0x0006,
    EACH_QUORUM=0x0007,
    SERIAL=0x0008,
    LOCAL_SERIAL=0x0009,
    LOCAL_ONE=0x000A
  },
  batch_types = {
    LOGGED=0,
    UNLOGGED=1,
    COUNTER=2
  },
  query_flags = {
    VALUES=0x01,
    PAGE_SIZE=0x04,
    PAGING_STATE=0x08
  },
  rows_flags = {
    GLOBAL_TABLES_SPEC=0x01,
    HAS_MORE_PAGES=0x02,
    -- 0x03
    NO_METADATA=0x04
  },
  result_kinds = {
    VOID=0x01,
    ROWS=0x02,
    SET_KEYSPACE=0x03,
    PREPARED=0x04,
    SCHEMA_CHANGE=0x05
  },
  error_codes = {
    [0x0000]="Server error",
    [0x000A]="Protocol error",
    [0x0100]="Bad credentials",
    [0x1000]="Unavailable exception",
    [0x1001]="Overloaded",
    [0x1002]="Is_bootstrapping",
    [0x1003]="Truncate_error",
    [0x1100]="Write_timeout",
    [0x1200]="Read_timeout",
    [0x2000]="Syntax_error",
    [0x2100]="Unauthorized",
    [0x2200]="Invalid",
    [0x2300]="Config_error",
    [0x2400]="Already_exists",
    [0x2500]="Unprepared"
  },
  types = {
    custom=0x00,
    ascii=0x01,
    bigint=0x02,
    blob=0x03,
    boolean=0x04,
    counter=0x05,
    decimal=0x06,
    double=0x07,
    float=0x08,
    int=0x09,
    text=0x0A,
    timestamp=0x0B,
    uuid=0x0C,
    varchar=0x0D,
    varint=0x0E,
    timeuuid=0x0F,
    inet=0x10,
    list=0x20,
    map=0x21,
    set=0x22
  }
}
