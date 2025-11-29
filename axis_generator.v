// ===============================================================
// AXI4-Stream Incrementer + AXI4-Lite Configuration
// - 1 always block = 1 signal control
// - 32-bit AXI4-Stream output (incrementing data)
// - AXI4-Lite 32-bit / 8-bit address
// - Reset: active-low, asynchronous
// ===============================================================

module axi4s_incrementer #
(
    parameter AXIS_DATA_WIDTH = 32
)
(
    input  wire                clk,
    input  wire                rst_n,     // active-low async reset

    // ----------------------------
    // AXI4-Stream Master Output
    // ----------------------------
    output reg  [31:0]         m_axis_tdata,
    output reg                 m_axis_tvalid,
    input  wire                m_axis_tready,
    output reg  [3:0]          m_axis_tstrb,
    output reg  [3:0]          m_axis_tkeep,
    output reg                 m_axis_tlast,
    output reg  [7:0]          m_axis_tid,

    // ----------------------------
    // AXI4-Lite Slave Interface
    // ----------------------------

    // Write Address
    input  wire [7:0]          s_axi_awaddr,
    input  wire                s_axi_awvalid,
    output reg                 s_axi_awready,

    // Write Data
    input  wire [31:0]         s_axi_wdata,
    input  wire [3:0]          s_axi_wstrb,
    input  wire                s_axi_wvalid,
    output reg                 s_axi_wready,

    // Write Response
    output reg  [1:0]          s_axi_bresp,
    output reg                 s_axi_bvalid,
    input  wire                s_axi_bready,

    // Read Address
    input  wire [7:0]          s_axi_araddr,
    input  wire                s_axi_arvalid,
    output reg                 s_axi_arready,

    // Read Data
    output reg  [31:0]         s_axi_rdata,
    output reg  [1:0]          s_axi_rresp,
    output reg                 s_axi_rvalid,
    input  wire                s_axi_rready
);

// ===============================================================
// 内部レジスタ
// ===============================================================
reg [31:0] reg_init_value;      // 0x00
reg [31:0] reg_data_size;       // 0x04
reg [31:0] counter;             // increment counter
reg        busy;                // streaming busy flag
reg        start;               // internal start pulse

wire write_fire  = s_axi_awvalid & s_axi_wvalid & s_axi_awready & s_axi_wready;
wire read_fire   = s_axi_arvalid & s_axi_arready;

// ==============================================================
// AXI-Lite Write Channel
// ==============================================================

// s_axi_awready
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axi_awready <= 0;
    else        s_axi_awready <= (!s_axi_awready && s_axi_awvalid && s_axi_wvalid);
end

// s_axi_wready
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axi_wready <= 0;
    else        s_axi_wready <= (!s_axi_wready && s_axi_awvalid && s_axi_wvalid);
end

// s_axi_bvalid
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axi_bvalid <= 0;
    else if (write_fire)     s_axi_bvalid <= 1;
    else if (s_axi_bready)   s_axi_bvalid <= 0;
end

// s_axi_bresp (always OKAY)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)              s_axi_bresp <= 2'b00;
    else if (write_fire)     s_axi_bresp <= 2'b00;
end

// レジスタ書き込み（reg_init_value）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) reg_init_value <= 32'd0;
    else if (write_fire && s_axi_awaddr[7:2] == 6'h00)
        reg_init_value <= s_axi_wdata;
end

// レジスタ書き込み（reg_data_size）
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) reg_data_size <= 32'd0;
    else if (write_fire && s_axi_awaddr[7:2] == 6'h01)
        reg_data_size <= s_axi_wdata;
end

// Start pulse (write to 0x00)
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) start <= 0;
    else if (write_fire && s_axi_awaddr[7:2] == 6'h02)
        start <= 1;
    else
        start <= 0;
end

// ==============================================================
// AXI-Lite Read Channel
// ==============================================================

// s_axi_arready
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axi_arready <= 0;
    else        s_axi_arready <= (!s_axi_arready && s_axi_arvalid);
end

// s_axi_rvalid
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axi_rvalid <= 0;
    else if (read_fire)      s_axi_rvalid <= 1;
    else if (s_axi_rready)   s_axi_rvalid <= 0;
end

// s_axi_rresp
always @(posedge clk or negedge rst_n) begin
    if (!rst_n)              s_axi_rresp <= 2'b00;
    else if (read_fire)      s_axi_rresp <= 2'b00;
end

// s_axi_rdata
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) s_axi_rdata <= 32'd0;
    else if (read_fire) begin
        case (s_axi_araddr[7:2])
            6'h00: s_axi_rdata <= reg_init_value;
            6'h01: s_axi_rdata <= reg_data_size;
            6'h02: s_axi_rdata <= {31'd0, busy};
            default: s_axi_rdata <= 32'd0;
        endcase
    end
end

// ==============================================================
// ストリーミング制御部
// ==============================================================

// busy
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) busy <= 0;
    else if (start) busy <= 1;
    else if (m_axis_tvalid && m_axis_tready && (counter == reg_data_size - 1))
        busy <= 0;
end

// counter
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) counter <= 32'd0;
    else if (start) counter <= 32'd0;
    else if (m_axis_tvalid && m_axis_tready && busy)
        counter <= counter + 1;
end

// m_axis_tvalid
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) m_axis_tvalid <= 0;
    else if (start && reg_data_size != 0) m_axis_tvalid <= 1;
    else if (m_axis_tvalid && m_axis_tready && (counter == reg_data_size - 1))
        m_axis_tvalid <= 0;
end

// m_axis_tdata
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) m_axis_tdata <= 32'd0;
    else if (start) m_axis_tdata <= reg_init_value;
    else if (m_axis_tvalid && m_axis_tready)
        m_axis_tdata <= m_axis_tdata + 1;
end

// m_axis_tlast
always @(posedge clk or negedge rst_n) begin
    if (!rst_n) m_axis_tlast <= 0;
    else if (m_axis_tvalid && m_axis_tready && (counter == reg_data_size - 1))
        m_axis_tlast <= 1;
    else if (m_axis_tready)
        m_axis_tlast <= 0;
end

// m_axis_tstrb / m_axis_tkeep / m_axis_tid は固定
always @(posedge clk or negedge rst_n)
    if (!rst_n) m_axis_tstrb <= 4'hF; else m_axis_tstrb <= 4'hF;

always @(posedge clk or negedge rst_n)
    if (!rst_n) m_axis_tkeep <= 4'hF; else m_axis_tkeep <= 4'hF;

always @(posedge clk or negedge rst_n)
    if (!rst_n) m_axis_tid <= 8'h00; else m_axis_tid <= 8'h00;

endmodule
