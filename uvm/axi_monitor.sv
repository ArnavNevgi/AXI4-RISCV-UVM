class axi_monitor extends uvm_component;

  `uvm_component_utils(axi_monitor)

  virtual axi_if vif;

  uvm_analysis_port #(axi_transaction) ap;

  string monitor_name;

  function new(string name = "axi_monitor", uvm_component parent = null);
    super.new(name, parent);
    ap = new("ap", this);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    if (!uvm_config_db#(virtual axi_if)::get(this, "", "vif", vif)) begin
      `uvm_fatal("NOVIF", $sformatf("No virtual interface set for %s", get_full_name()))
    end

    if (!uvm_config_db#(string)::get(this, "", "monitor_name", monitor_name)) begin
      monitor_name = get_name();
    end
  endfunction

  task run_phase(uvm_phase phase);
    fork
      monitor_write_channel();
      monitor_read_channel();
    join
  endtask

  task monitor_write_channel();
    bit [31:0] active_aw_addr;
    bit [7:0]  active_aw_len;
    bit [3:0]  active_aw_id;
    bit        have_aw;
    int        beat_count;

    axi_transaction tr;

    have_aw = 1'b0;
    beat_count = 0;

    forever begin
      @(posedge vif.clk);

      if (!vif.rst_n) begin
        have_aw = 1'b0;
        beat_count = 0;
      end
      else begin

        if (vif.aw_valid && vif.aw_ready) begin
          if (have_aw) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s AW accepted while previous write burst still active",
                                 monitor_name))
          end

          active_aw_addr = vif.aw.addr;
          active_aw_len  = vif.aw.len;
          active_aw_id   = vif.aw.id;
          have_aw        = 1'b1;
          beat_count     = 0;

          `uvm_info("AXI_MON",
                    $sformatf("%s AW addr=0x%08h len=%0d id=%0d",
                              monitor_name, active_aw_addr, active_aw_len, active_aw_id),
                    UVM_MEDIUM)
        end

        if (vif.w_valid && vif.w_ready) begin
          if (!have_aw) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s W beat accepted before AW", monitor_name))
          end

          tr = axi_transaction::type_id::create("tr");
          tr.kind = axi_transaction::AXI_WRITE;
          tr.id   = active_aw_id;
          tr.addr = active_aw_addr + (beat_count * 4);
          tr.data = vif.w.data;
          tr.len  = active_aw_len;
          tr.last = vif.w.last;
          tr.resp = 2'b00;

          ap.write(tr);

          if ((beat_count < active_aw_len) && vif.w.last) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s early WLAST beat=%0d len=%0d",
                                 monitor_name, beat_count, active_aw_len))
          end

          if ((beat_count == active_aw_len) && !vif.w.last) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s missing WLAST on final beat=%0d len=%0d",
                                 monitor_name, beat_count, active_aw_len))
          end

          if (beat_count > active_aw_len) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s excess W beat=%0d len=%0d",
                                 monitor_name, beat_count, active_aw_len))
          end

          `uvm_info("AXI_MON",
                    $sformatf("%s W beat=%0d %s",
                              monitor_name, beat_count, tr.convert2string()),
                    UVM_MEDIUM)

          beat_count++;

          if (vif.w.last) begin
            have_aw = 1'b0;
          end
        end

        if (vif.b_valid && vif.b_ready) begin
          if (vif.b.resp != AXI_RESP_OKAY) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s B response error resp=%0d id=%0d",
                                 monitor_name, vif.b.resp, vif.b.id))
          end

          `uvm_info("AXI_MON",
                    $sformatf("%s B resp=%0d id=%0d",
                              monitor_name, vif.b.resp, vif.b.id),
                    UVM_MEDIUM)
        end

      end
    end
  endtask

  task monitor_read_channel();
    bit [31:0] active_ar_addr;
    bit [7:0]  active_ar_len;
    bit [3:0]  active_ar_id;
    bit        have_ar;
    int        beat_count;

    axi_transaction tr;

    have_ar = 1'b0;
    beat_count = 0;

    forever begin
      @(posedge vif.clk);

      if (!vif.rst_n) begin
        have_ar = 1'b0;
        beat_count = 0;
      end
      else begin

        if (vif.ar_valid && vif.ar_ready) begin
          if (have_ar) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s AR accepted while previous read burst still active",
                                 monitor_name))
          end

          active_ar_addr = vif.ar.addr;
          active_ar_len  = vif.ar.len;
          active_ar_id   = vif.ar.id;
          have_ar        = 1'b1;
          beat_count     = 0;

          `uvm_info("AXI_MON",
                    $sformatf("%s AR addr=0x%08h len=%0d id=%0d",
                              monitor_name, active_ar_addr, active_ar_len, active_ar_id),
                    UVM_MEDIUM)
        end

        if (vif.r_valid && vif.r_ready) begin
          if (!have_ar) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s R beat accepted before AR", monitor_name))
          end

          tr = axi_transaction::type_id::create("tr");
          tr.kind = axi_transaction::AXI_READ;
          tr.id   = active_ar_id;
          tr.addr = active_ar_addr + (beat_count * 4);
          tr.data = vif.r.data;
          tr.len  = active_ar_len;
          tr.last = vif.r.last;
          tr.resp = vif.r.resp;

          ap.write(tr);

          if (vif.r.resp != AXI_RESP_OKAY) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s R response error beat=%0d resp=%0d",
                                 monitor_name, beat_count, vif.r.resp))
          end

          if ((beat_count < active_ar_len) && vif.r.last) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s early RLAST beat=%0d len=%0d",
                                 monitor_name, beat_count, active_ar_len))
          end

          if ((beat_count == active_ar_len) && !vif.r.last) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s missing RLAST on final beat=%0d len=%0d",
                                 monitor_name, beat_count, active_ar_len))
          end

          if (beat_count > active_ar_len) begin
            `uvm_error("AXI_MON",
                       $sformatf("%s excess R beat=%0d len=%0d",
                                 monitor_name, beat_count, active_ar_len))
          end

          `uvm_info("AXI_MON",
                    $sformatf("%s R beat=%0d %s",
                              monitor_name, beat_count, tr.convert2string()),
                    UVM_MEDIUM)

          beat_count++;

          if (vif.r.last) begin
            have_ar = 1'b0;
          end
        end

      end
    end
  endtask

endclass