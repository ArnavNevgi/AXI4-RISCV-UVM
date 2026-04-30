import axi_pkg::*;

interface axi_if #(parameter ID_W=4, ADDR_W=32, DATA_W=32)
                  (input logic clk, rst_n);

  localparam STRB_W = DATA_W/8;

  // ---------------- WRITE ADDRESS CHANNEL ----------------
  // logic              aw_valid;
  // logic              aw_ready;
  // logic [ID_W-1:0]   aw_id;
  // logic [ADDR_W-1:0] aw_addr;
  // logic [7:0]        aw_len;
  // logic [2:0]        aw_size;
  // logic [1:0]        aw_burst;
  logic aw_valid, aw_ready;
  axi_aw_ar_t aw;

  // ---------------- WRITE DATA CHANNEL ----------------
  // logic              w_valid;
  // logic              w_ready;
  // logic [DATA_W-1:0] w_data;
  // logic [STRB_W-1:0] w_strb;
  // logic              w_last;

  logic w_valid, w_ready;
  axi_w_t w;  

  // ---------------- WRITE RESPONSE CHANNEL ----------------
  // logic              b_valid;
  // logic              b_ready;
  // logic [ID_W-1:0]   b_id;
  // logic [1:0]        b_resp;

  logic b_valid, b_ready;
  axi_b_t b;
  
  // ---------------- READ ADDRESS CHANNEL ----------------
  // logic              ar_valid;
  // logic              ar_ready;
  // logic [ID_W-1:0]   ar_id;
  // logic [ADDR_W-1:0] ar_addr;
  // logic [7:0]        ar_len;
  // logic [2:0]        ar_size;
  // logic [1:0]        ar_burst;

  logic ar_valid, ar_ready;
  axi_aw_ar_t ar;

  // ---------------- READ DATA CHANNEL ----------------
  // logic              r_valid;
  // logic              r_ready;
  // logic [ID_W-1:0]   r_id;
  // logic [DATA_W-1:0] r_data;
  // logic [1:0]        r_resp;
  // logic              r_last;

  logic r_valid, r_ready;
  axi_r_t r;

  // ---------------- BASIC ASSERTIONS ----------------
  // VALID must remain stable until READY

 property stable_aw;
  @(posedge clk) disable iff(!rst_n)
    (aw_valid && !aw_ready) |=> (aw_valid && $stable(aw));
endproperty

assert property(stable_aw);

property stable_w;
  @(posedge clk) disable iff(!rst_n)
    (w_valid && !w_ready) |=> (w_valid && $stable(w));
endproperty

assert property(stable_w);

property stable_ar;
  @(posedge clk) disable iff(!rst_n)
    (ar_valid && !ar_ready) |=> (ar_valid && $stable(ar));
endproperty

assert property(stable_ar);



  // // ---------------- MODPORTS ----------------

  // ---------------- MODPORTS ----------------
modport master (
  input clk, rst_n,

  // Write Address
  output aw_valid,
  output aw,
  input  aw_ready,

  // Write Data
  output w_valid,
  output w,
  input  w_ready,

  // Write Response
  input  b_valid,
  input  b,
  output b_ready,

  // Read Address
  output ar_valid,
  output ar,
  input  ar_ready,

  // Read Data
  input  r_valid,
  input  r,
  output r_ready
);

modport slave (
  input clk, rst_n,

  // Write Address
  input  aw_valid,
  input  aw,
  output aw_ready,

  // Write Data
  input  w_valid,
  input  w,
  output w_ready,

  // Write Response
  output b_valid,
  output b,
  input  b_ready,

  // Read Address
  input  ar_valid,
  input  ar,
  output ar_ready,

  // Read Data
  output r_valid,
  output r,
  input  r_ready
);

  // modport master (
  //   input clk, rst_n,

  //   output aw_valid, aw_id, aw_addr, aw_len, aw_size, aw_burst,
  //   input  aw_ready,

  //   output w_valid, w_data, w_strb, w_last,
  //   input  w_ready,

  //   input  b_valid, b_id, b_resp,
  //   output b_ready,

  //   output ar_valid, ar_id, ar_addr, ar_len, ar_size, ar_burst,
  //   input  ar_ready,

  //   input  r_valid, r_id, r_data, r_resp, r_last,
  //   output r_ready
  // );

  // modport slave (
  //   input clk, rst_n,

  //   input  aw_valid, aw_id, aw_addr, aw_len, aw_size, aw_burst,
  //   output aw_ready,

  //   input  w_valid, w_data, w_strb, w_last,
  //   output w_ready,

  //   output b_valid, b_id, b_resp,
  //   input  b_ready,

  //   input  ar_valid, ar_id, ar_addr, ar_len, ar_size, ar_burst,
  //   output ar_ready,

  //   output r_valid, r_id, r_data, r_resp, r_last,
  //   input  r_ready
  // );

endinterface