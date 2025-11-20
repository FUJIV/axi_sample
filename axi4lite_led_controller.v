`timescale 1ns / 1ps

module axi4lite_led_controller #(
    parameter integer DATA_WIDTH = 32,
    parameter integer ADDR_WIDTH = 32,
    parameter integer LED_WIDTH  = 8
)(
    input  wire                         s_axi_aclk,
    input  wire                         s_axi_aresetn,

    // Write Address Channel
    input  wire [ADDR_WIDTH-1:0]        s_axi_awaddr,
    input  wire                         s_axi_awvalid,
    output reg                          s_axi_awready,

    // Write Data Channel
    input  wire [DATA_WIDTH-1:0]        s_axi_wdata,
    input  wire [(DATA_WIDTH/8)-1:0]    s_axi_wstrb,
    input  wire                         s_axi_wvalid,
    output reg                          s_axi_wready,

    // Write Response Channel
    output reg [1:0]                    s_axi_bresp,
    output reg                          s_axi_bvalid,
    input  wire                         s_axi_bready,

    // Read Address Channel
    input  wire [ADDR_WIDTH-1:0]        s_axi_araddr,
    input  wire                         s_axi_arvalid,
    output reg                          s_axi_arready,

    // Read Data Channel
    output reg [DATA_WIDTH-1:0]         s_axi_rdata,
    output reg [1:0]                    s_axi_rresp,
    output reg                          s_axi_rvalid,
    input  wire                         s_axi_rready,

    // LED Output
    output reg [LED_WIDTH-1:0]          leds
);

    // Register map
    localparam ADDR_LED = 8'h00;

    // Address decoding (byte address)
    wire [7:0] awaddr_b = s_axi_awaddr[7:0];
    wire [7:0] araddr_b = s_axi_araddr[7:0];

    // Internal register
    reg [DATA_WIDTH-1:0] reg_led;

    // Write enable detection
    wire aw_w_handshake = (s_axi_awvalid && s_axi_wvalid && !s_axi_bvalid);

    // =========================================================
    // s_axi_awready
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_awready <= 1'b0;
        else
            s_axi_awready <= (aw_w_handshake & ~s_axi_awready);
    end

    // =========================================================
    // s_axi_wready
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_wready <= 1'b0;
        else
            s_axi_wready <= (aw_w_handshake & ~s_axi_wready);
    end

    // =========================================================
    // reg_led
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            reg_led <= {DATA_WIDTH{1'b0}};
        else if (s_axi_awready && s_axi_wready) begin
            integer i;
            if (awaddr_b == ADDR_LED) begin
                for (i = 0; i < (DATA_WIDTH/8); i = i + 1)
                    if (s_axi_wstrb[i])
                        reg_led[i*8 +: 8] <= s_axi_wdata[i*8 +: 8];
            end
        end
    end

    // =========================================================
    // LED output
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            leds <= {LED_WIDTH{1'b0}};
        else
            leds <= reg_led[LED_WIDTH-1:0];
    end

    // =========================================================
    // s_axi_bvalid
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_bvalid <= 1'b0;
        else if (s_axi_awready && s_axi_wready)
            s_axi_bvalid <= 1'b1;
        else if (s_axi_bready)
            s_axi_bvalid <= 1'b0;
    end

    // =========================================================
    // s_axi_bresp
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_bresp <= 2'b00;
        else if (s_axi_awready && s_axi_wready)
            s_axi_bresp <= 2'b00;  // OKAY
    end

    // =========================================================
    // s_axi_arready
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_arready <= 1'b0;
        else
            s_axi_arready <= (s_axi_arvalid && !s_axi_rvalid);
    end

    // =========================================================
    // s_axi_rvalid
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_rvalid <= 1'b0;
        else if (s_axi_arready && s_axi_arvalid)
            s_axi_rvalid <= 1'b1;
        else if (s_axi_rready)
            s_axi_rvalid <= 1'b0;
    end

    // =========================================================
    // s_axi_rdata
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_rdata <= {DATA_WIDTH{1'b0}};
        else if (s_axi_arready && s_axi_arvalid) begin
            case (araddr_b)
                ADDR_LED: s_axi_rdata <= reg_led;
                default : s_axi_rdata <= {DATA_WIDTH{1'b0}};
            endcase
        end
    end

    // =========================================================
    // s_axi_rresp
    // =========================================================
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn)
            s_axi_rresp <= 2'b00;
        else if (s_axi_arready && s_axi_arvalid)
            s_axi_rresp <= 2'b00;  // OKAY
    end

endmodule
