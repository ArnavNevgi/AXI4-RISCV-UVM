`uvm_analysis_imp_decl(_cpu)
`uvm_analysis_imp_decl(_dma)

class soc_scoreboard extends uvm_component;

  `uvm_component_utils(soc_scoreboard)

  localparam bit [31:0] DMA_REG_CONTROL  = 32'h0001_0000;
  localparam bit [31:0] DMA_REG_SRC_ADDR = 32'h0001_0008;
  localparam bit [31:0] DMA_REG_DST_ADDR = 32'h0001_000C;
  localparam bit [31:0] DMA_REG_LENGTH   = 32'h0001_0010;

  localparam bit [31:0] DMA_REG_CONTROL_LOCAL  = 32'h0000_0000;
  localparam bit [31:0] DMA_REG_SRC_ADDR_LOCAL = 32'h0000_0008;
  localparam bit [31:0] DMA_REG_DST_ADDR_LOCAL = 32'h0000_000C;
  localparam bit [31:0] DMA_REG_LENGTH_LOCAL   = 32'h0000_0010;

  uvm_analysis_imp_cpu #(axi_transaction, soc_scoreboard) cpu_imp;
  uvm_analysis_imp_dma #(axi_transaction, soc_scoreboard) dma_imp;

  int cpu_write_count;
  int cpu_read_count;
  int dma_write_count;
  int dma_read_count;

  bit saw_dma_src_write;
  bit saw_dma_dst_write;
  bit saw_dma_len_write;
  bit saw_dma_start_write;

  int dma_copy_read_count;
  int dma_copy_write_count;
  int dma_copy_error_count;

  bit [31:0] dma_read_q[$];

  bit [31:0] dma_src_addr_exp;
  bit [31:0] dma_dst_addr_exp;
  int        dma_copy_words_exp;

  bit [31:0] cov_addr;
  bit [31:0] cov_data;
  bit [7:0]  cov_len;
  bit        cov_last;
  bit        cov_is_write;
  bit        cov_is_cpu;
  bit        cov_is_dma;

  covergroup soc_axi_cg;
    option.per_instance = 1;

    cp_agent: coverpoint {cov_is_cpu, cov_is_dma} {
      bins cpu = {2'b10};
      bins dma = {2'b01};
    }

    cp_kind: coverpoint cov_is_write {
      bins read  = {0};
      bins write = {1};
    }

    cp_cpu_reg_addr: coverpoint cov_addr iff (cov_is_cpu && cov_is_write) {
      bins control  = {DMA_REG_CONTROL,  DMA_REG_CONTROL_LOCAL};
      bins src_addr = {DMA_REG_SRC_ADDR, DMA_REG_SRC_ADDR_LOCAL};
      bins dst_addr = {DMA_REG_DST_ADDR, DMA_REG_DST_ADDR_LOCAL};
      bins length   = {DMA_REG_LENGTH,   DMA_REG_LENGTH_LOCAL};
    }

    cp_dma_src_addr: coverpoint cov_addr iff (cov_is_dma && !cov_is_write) {
      bins low_sram  = {[32'h0000_0000:32'h0000_00FF]};
      bins high_sram = {[32'h0000_0100:32'h0000_01FF]};
    }

    cp_dma_dst_addr: coverpoint cov_addr iff (cov_is_dma && cov_is_write) {
      bins low_sram  = {[32'h0000_0000:32'h0000_00FF]};
      bins high_sram = {[32'h0000_0100:32'h0000_01FF]};
    }

    cp_len: coverpoint cov_len {
      bins single   = {0};
      bins burst_8  = {7};
      bins burst_16 = {15};
      bins other[]  = {[1:6], [8:14]};
    }

    cp_last: coverpoint cov_last {
      bins not_last = {0};
      bins last     = {1};
    }

    cross_agent_kind: cross cp_agent, cp_kind;
  endgroup

  function new(string name = "soc_scoreboard", uvm_component parent = null);
    super.new(name, parent);

    cpu_imp = new("cpu_imp", this);
    dma_imp = new("dma_imp", this);

    soc_axi_cg = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    cpu_write_count = 0;
    cpu_read_count  = 0;
    dma_write_count = 0;
    dma_read_count  = 0;

    saw_dma_src_write   = 1'b0;
    saw_dma_dst_write   = 1'b0;
    saw_dma_len_write   = 1'b0;
    saw_dma_start_write = 1'b0;

    dma_copy_read_count  = 0;
    dma_copy_write_count = 0;
    dma_copy_error_count = 0;

    dma_read_q.delete();

    if (!uvm_config_db#(bit [31:0])::get(this, "", "dma_src_addr_exp", dma_src_addr_exp)) begin
      dma_src_addr_exp = 32'h0000_0040;
      `uvm_warning("SOC_SCB", "dma_src_addr_exp not configured, using default 0x00000040")
    end

    if (!uvm_config_db#(bit [31:0])::get(this, "", "dma_dst_addr_exp", dma_dst_addr_exp)) begin
      dma_dst_addr_exp = 32'h0000_0180;
      `uvm_warning("SOC_SCB", "dma_dst_addr_exp not configured, using default 0x00000180")
    end

    if (!uvm_config_db#(int)::get(this, "", "dma_copy_words_exp", dma_copy_words_exp)) begin
      dma_copy_words_exp = 16;
      `uvm_warning("SOC_SCB", "dma_copy_words_exp not configured, using default 16")
    end

    `uvm_info("SOC_SCB",
              $sformatf("Configured expected DMA copy: src=0x%08h dst=0x%08h words=%0d",
                        dma_src_addr_exp, dma_dst_addr_exp, dma_copy_words_exp),
              UVM_LOW)
  endfunction

  function bit addr_in_dma_src_range(bit [31:0] addr);
    begin
      addr_in_dma_src_range =
        (addr >= dma_src_addr_exp) &&
        (addr < (dma_src_addr_exp + (dma_copy_words_exp * 4)));
    end
  endfunction

  function bit addr_in_dma_dst_range(bit [31:0] addr);
    begin
      addr_in_dma_dst_range =
        (addr >= dma_dst_addr_exp) &&
        (addr < (dma_dst_addr_exp + (dma_copy_words_exp * 4)));
    end
  endfunction

  function void sample_cov(axi_transaction tr, bit is_cpu, bit is_dma);
    cov_addr     = tr.addr;
    cov_data     = tr.data;
    cov_len      = tr.len;
    cov_last     = tr.last;
    cov_is_write = (tr.kind == axi_transaction::AXI_WRITE);
    cov_is_cpu   = is_cpu;
    cov_is_dma   = is_dma;

    soc_axi_cg.sample();
  endfunction

  function bit is_dma_reg_addr(bit [31:0] addr, bit [31:0] full_addr, bit [31:0] local_addr);
    begin
      is_dma_reg_addr = (addr == full_addr) || (addr == local_addr);
    end
  endfunction

  function void check_cpu_reg_write(axi_transaction tr);
    if (is_dma_reg_addr(tr.addr, DMA_REG_SRC_ADDR, DMA_REG_SRC_ADDR_LOCAL)) begin
      if (tr.data == dma_src_addr_exp) begin
        saw_dma_src_write = 1'b1;
      end
      else begin
        `uvm_error("SOC_SCB",
                   $sformatf("CPU wrote wrong DMA SRC_ADDR. expected=0x%08h got=0x%08h",
                             dma_src_addr_exp, tr.data))
      end
    end
    else if (is_dma_reg_addr(tr.addr, DMA_REG_DST_ADDR, DMA_REG_DST_ADDR_LOCAL)) begin
      if (tr.data == dma_dst_addr_exp) begin
        saw_dma_dst_write = 1'b1;
      end
      else begin
        `uvm_error("SOC_SCB",
                   $sformatf("CPU wrote wrong DMA DST_ADDR. expected=0x%08h got=0x%08h",
                             dma_dst_addr_exp, tr.data))
      end
    end
    else if (is_dma_reg_addr(tr.addr, DMA_REG_LENGTH, DMA_REG_LENGTH_LOCAL)) begin
      if (tr.data == dma_copy_words_exp) begin
        saw_dma_len_write = 1'b1;
      end
      else begin
        `uvm_error("SOC_SCB",
                   $sformatf("CPU wrote wrong DMA LENGTH. expected=%0d got=0x%08h",
                             dma_copy_words_exp, tr.data))
      end
    end
    else if (is_dma_reg_addr(tr.addr, DMA_REG_CONTROL, DMA_REG_CONTROL_LOCAL)) begin
      if (tr.data == 32'h0000_0001) begin
        saw_dma_start_write = 1'b1;
      end
      else begin
        `uvm_error("SOC_SCB",
                   $sformatf("CPU wrote wrong DMA CONTROL.START value. expected=1 got=0x%08h",
                             tr.data))
      end
    end
  endfunction

  function void write_cpu(axi_transaction tr);
    sample_cov(tr, 1'b1, 1'b0);

    if (tr.kind == axi_transaction::AXI_WRITE) begin
      cpu_write_count++;
      check_cpu_reg_write(tr);

      `uvm_info("SOC_SCB",
                $sformatf("CPU WRITE observed: %s", tr.convert2string()),
                UVM_MEDIUM)
    end
    else begin
      cpu_read_count++;

      `uvm_info("SOC_SCB",
                $sformatf("CPU READ observed: %s", tr.convert2string()),
                UVM_MEDIUM)
    end
  endfunction

  function void write_dma(axi_transaction tr);
    bit [31:0] expected_data;

    sample_cov(tr, 1'b0, 1'b1);

    if (tr.kind == axi_transaction::AXI_READ) begin
      dma_read_count++;

      if (!addr_in_dma_src_range(tr.addr)) begin
        `uvm_error("SOC_SCB",
                   $sformatf("DMA READ outside expected source range: %s",
                             tr.convert2string()))
        dma_copy_error_count++;
      end
      else begin
        dma_copy_read_count++;
        dma_read_q.push_back(tr.data);

        `uvm_info("SOC_SCB",
                  $sformatf("DMA READ captured: addr=0x%08h data=0x%08h queue_depth=%0d",
                            tr.addr, tr.data, dma_read_q.size()),
                  UVM_MEDIUM)
      end
    end
    else begin
      dma_write_count++;

      if (!addr_in_dma_dst_range(tr.addr)) begin
        `uvm_error("SOC_SCB",
                   $sformatf("DMA WRITE outside expected destination range: %s",
                             tr.convert2string()))
        dma_copy_error_count++;
      end
      else begin
        dma_copy_write_count++;

        if (dma_read_q.size() == 0) begin
          `uvm_error("SOC_SCB",
                     $sformatf("DMA WRITE has no matching prior READ: addr=0x%08h data=0x%08h",
                               tr.addr, tr.data))
          dma_copy_error_count++;
        end
        else begin
          expected_data = dma_read_q.pop_front();

          if (tr.data !== expected_data) begin
            `uvm_error("SOC_SCB",
                       $sformatf("DMA COPY DATA MISMATCH: addr=0x%08h expected=0x%08h got=0x%08h",
                                 tr.addr, expected_data, tr.data))
            dma_copy_error_count++;
          end
          else begin
            `uvm_info("SOC_SCB",
                      $sformatf("DMA COPY DATA PASS: addr=0x%08h data=0x%08h",
                                tr.addr, tr.data),
                      UVM_LOW)
          end
        end
      end
    end
  endfunction

  function void check_phase(uvm_phase phase);
    super.check_phase(phase);

    if (!saw_dma_src_write)
      `uvm_error("SOC_SCB", "CPU did not write expected DMA SRC_ADDR register value")

    if (!saw_dma_dst_write)
      `uvm_error("SOC_SCB", "CPU did not write expected DMA DST_ADDR register value")

    if (!saw_dma_len_write)
      `uvm_error("SOC_SCB", "CPU did not write expected DMA LENGTH register value")

    if (!saw_dma_start_write)
      `uvm_error("SOC_SCB", "CPU did not write DMA CONTROL.START = 1")

    if (dma_read_count != dma_copy_words_exp) begin
      `uvm_error("SOC_SCB",
                 $sformatf("Expected %0d total DMA reads, observed %0d",
                           dma_copy_words_exp, dma_read_count))
    end

    if (dma_write_count != dma_copy_words_exp) begin
      `uvm_error("SOC_SCB",
                 $sformatf("Expected %0d total DMA writes, observed %0d",
                           dma_copy_words_exp, dma_write_count))
    end

    if (dma_copy_read_count != dma_copy_words_exp) begin
      `uvm_error("SOC_SCB",
                 $sformatf("Expected %0d DMA copy reads, observed %0d",
                           dma_copy_words_exp, dma_copy_read_count))
    end

    if (dma_copy_write_count != dma_copy_words_exp) begin
      `uvm_error("SOC_SCB",
                 $sformatf("Expected %0d DMA copy writes, observed %0d",
                           dma_copy_words_exp, dma_copy_write_count))
    end

    if (dma_read_q.size() != 0) begin
      `uvm_error("SOC_SCB",
                 $sformatf("DMA read queue not empty at end. Remaining=%0d",
                           dma_read_q.size()))
    end

    if (dma_copy_error_count != 0) begin
      `uvm_error("SOC_SCB",
                 $sformatf("DMA copy scoreboard errors=%0d",
                           dma_copy_error_count))
    end
  endfunction

  function void report_phase(uvm_phase phase);
    super.report_phase(phase);

    `uvm_info("SOC_SCB",
              $sformatf("SUMMARY cpu_writes=%0d cpu_reads=%0d dma_writes=%0d dma_reads=%0d dma_copy_reads=%0d dma_copy_writes=%0d copy_errors=%0d coverage=%.2f%%",
                        cpu_write_count,
                        cpu_read_count,
                        dma_write_count,
                        dma_read_count,
                        dma_copy_read_count,
                        dma_copy_write_count,
                        dma_copy_error_count,
                        soc_axi_cg.get_coverage()),
              UVM_LOW)
  endfunction

endclass
