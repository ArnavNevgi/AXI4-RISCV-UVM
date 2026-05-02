package axi_pkg;

  // ---------------- PARAMETERS ----------------
  parameter int AXI_ID_W   = 4;
  parameter int AXI_ADDR_W = 32;
  parameter int AXI_DATA_W = 32;

  localparam int AXI_STRB_W = AXI_DATA_W / 8;

  // ---------------- ENUMS ----------------

  // Burst types
  typedef enum logic [1:0] {
    AXI_BURST_FIXED = 2'b00,
    AXI_BURST_INCR  = 2'b01,
    AXI_BURST_WRAP  = 2'b10
  } axi_burst_t;

  // Response types
  typedef enum logic [1:0] {
    AXI_RESP_OKAY   = 2'b00,
    AXI_RESP_EXOKAY = 2'b01,
    AXI_RESP_SLVERR = 2'b10,
    AXI_RESP_DECERR = 2'b11
  } axi_resp_t;

  // ---------------- CHANNEL STRUCTS ----------------

  // Write Address / Read Address (same fields)
  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_ADDR_W-1:0] addr;
    logic [7:0]            len;
    logic [2:0]            size;
    axi_burst_t            burst;
  } axi_aw_ar_t;

  // Write Data
  typedef struct packed {
    logic [AXI_DATA_W-1:0] data;
    logic [AXI_STRB_W-1:0] strb;
    logic                  last;
  } axi_w_t;

  // Write Response
  typedef struct packed {
    logic [AXI_ID_W-1:0] id;
    axi_resp_t           resp;
  } axi_b_t;

  // Read Data
  typedef struct packed {
    logic [AXI_ID_W-1:0]   id;
    logic [AXI_DATA_W-1:0] data;
    axi_resp_t             resp;
    logic                  last;
  } axi_r_t;

endpackage