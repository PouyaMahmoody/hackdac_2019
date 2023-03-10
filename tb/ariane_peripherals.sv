// Copyright 2018 ETH Zurich and University of Bologna.
// Copyright and related rights are licensed under the Solderpad Hardware
// License, Version 0.51 (the "License"); you may not use this file except in
// compliance with the License.  You may obtain a copy of the License at
// http://solderpad.org/licenses/SHL-0.51. Unless required by applicable law
// or agreed to in writing, software, hardware and materials distributed under
// this License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR
// CONDITIONS OF ANY KIND, either express or implied. See the License for the
// specific language governing permissions and limitations under the License.

// Xilinx Peripehrals
module ariane_peripherals #(
    parameter int AxiAddrWidth = -1,
    parameter int AxiDataWidth = -1,
    parameter int AxiIdWidth   = -1,
    parameter int AxiUserWidth = 1,
    parameter bit InclUART     = 1,
    parameter bit InclSPI      = 0,
    parameter bit InclEthernet = 0,
    parameter bit InclGPIO     = 0
) (
    input  logic               clk_i           , // Clock
    input  logic               rst_ni          , // Asynchronous reset active low
    AXI_BUS.in                 plic            ,
    AXI_BUS.in                 aes             , 
    AXI_BUS.in                 rom2_fuse       ,
    AXI_BUS.in                 pkt             ,
    AXI_BUS.in                 uart            ,
    AXI_BUS.in                 spi             ,
    AXI_BUS.in                 ethernet        ,
    output logic [31:0]        jtag_key        , 
    output logic [1:0][47:0]   access_ctrl_reg , 
    output logic [1:0]         irq_o           ,
    // UART
    input  logic               rx_i            ,
    output logic               tx_o            ,
    // Ethernet
    input  wire                eth_txck        ,
    input  wire                eth_rxck        ,
    input  wire                eth_rxctl       ,
    input  wire [3:0]          eth_rxd         ,
    output wire                eth_rst_n       ,
    output wire                eth_tx_en       ,
    output wire [3:0]          eth_txd         ,
    inout  wire                phy_mdio        ,
    output logic               eth_mdc         ,
    // MDIO Interface
    inout                      mdio            ,
    output                     mdc             ,
    // SPI
    output logic               spi_clk_o       ,
    output logic               spi_mosi        ,
    input  logic               spi_miso        ,
    output logic               spi_ss
);

    // ---------------
    // 1. PLIC
    // ---------------
    logic [ariane_soc::NumSources-1:0] irq_sources;

    REG_BUS #(
        .ADDR_WIDTH ( 32 ),
        .DATA_WIDTH ( 32 )
    ) reg_bus (clk_i);

    logic         plic_penable;
    logic         plic_pwrite;
    logic [31:0]  plic_paddr;
    logic         plic_psel;
    logic [31:0]  plic_pwdata;
    logic [31:0]  plic_prdata;
    logic         plic_pready;
    logic         plic_pslverr;

    axi2apb_64_32 #(
        .AXI4_ADDRESS_WIDTH ( AxiAddrWidth  ),
        .AXI4_RDATA_WIDTH   ( AxiDataWidth  ),
        .AXI4_WDATA_WIDTH   ( AxiDataWidth  ),
        .AXI4_ID_WIDTH      ( AxiIdWidth    ),
        .AXI4_USER_WIDTH    ( AxiUserWidth  ),
        .BUFF_DEPTH_SLAVE   ( 2             ),
        .APB_ADDR_WIDTH     ( 32            )
    ) i_axi2apb_64_32_plic (
        .ACLK      ( clk_i          ),
        .ARESETn   ( rst_ni         ),
        .test_en_i ( 1'b0           ),
        .AWID_i    ( plic.aw_id     ),
        .AWADDR_i  ( plic.aw_addr   ),
        .AWLEN_i   ( plic.aw_len    ),
        .AWSIZE_i  ( plic.aw_size   ),
        .AWBURST_i ( plic.aw_burst  ),
        .AWLOCK_i  ( plic.aw_lock   ),
        .AWCACHE_i ( plic.aw_cache  ),
        .AWPROT_i  ( plic.aw_prot   ),
        .AWREGION_i( plic.aw_region ),
        .AWUSER_i  ( plic.aw_user   ),
        .AWQOS_i   ( plic.aw_qos    ),
        .AWVALID_i ( plic.aw_valid  ),
        .AWREADY_o ( plic.aw_ready  ),
        .WDATA_i   ( plic.w_data    ),
        .WSTRB_i   ( plic.w_strb    ),
        .WLAST_i   ( plic.w_last    ),
        .WUSER_i   ( plic.w_user    ),
        .WVALID_i  ( plic.w_valid   ),
        .WREADY_o  ( plic.w_ready   ),
        .BID_o     ( plic.b_id      ),
        .BRESP_o   ( plic.b_resp    ),
        .BVALID_o  ( plic.b_valid   ),
        .BUSER_o   ( plic.b_user    ),
        .BREADY_i  ( plic.b_ready   ),
        .ARID_i    ( plic.ar_id     ),
        .ARADDR_i  ( plic.ar_addr   ),
        .ARLEN_i   ( plic.ar_len    ),
        .ARSIZE_i  ( plic.ar_size   ),
        .ARBURST_i ( plic.ar_burst  ),
        .ARLOCK_i  ( plic.ar_lock   ),
        .ARCACHE_i ( plic.ar_cache  ),
        .ARPROT_i  ( plic.ar_prot   ),
        .ARREGION_i( plic.ar_region ),
        .ARUSER_i  ( plic.ar_user   ),
        .ARQOS_i   ( plic.ar_qos    ),
        .ARVALID_i ( plic.ar_valid  ),
        .ARREADY_o ( plic.ar_ready  ),
        .RID_o     ( plic.r_id      ),
        .RDATA_o   ( plic.r_data    ),
        .RRESP_o   ( plic.r_resp    ),
        .RLAST_o   ( plic.r_last    ),
        .RUSER_o   ( plic.r_user    ),
        .RVALID_o  ( plic.r_valid   ),
        .RREADY_i  ( plic.r_ready   ),
        .PENABLE   ( plic_penable   ),
        .PWRITE    ( plic_pwrite    ),
        .PADDR     ( plic_paddr     ),
        .PSEL      ( plic_psel      ),
        .PWDATA    ( plic_pwdata    ),
        .PRDATA    ( plic_prdata    ),
        .PREADY    ( plic_pready    ),
        .PSLVERR   ( plic_pslverr   )
    );

    apb_to_reg i_apb_to_reg (
        .clk_i     ( clk_i        ),
        .rst_ni    ( rst_ni       ),
        .penable_i ( plic_penable ),
        .pwrite_i  ( plic_pwrite  ),
        .paddr_i   ( plic_paddr   ),
        .psel_i    ( plic_psel    ),
        .pwdata_i  ( plic_pwdata  ),
        .prdata_o  ( plic_prdata  ),
        .pready_o  ( plic_pready  ),
        .pslverr_o ( plic_pslverr ),
        .reg_o     ( reg_bus      )
    );

    plic #(
        .ID_BITWIDTH        ( ariane_soc::PLICIdWidth       ),
        .PARAMETER_BITWIDTH ( ariane_soc::ParameterBitwidth ),
        .NUM_TARGETS        ( ariane_soc::NumTargets        ),
        .NUM_SOURCES        ( ariane_soc::NumSources        )
    ) i_plic (
        .clk_i              ( clk_i                  ),
        .rst_ni             ( rst_ni                 ),
        .irq_sources_i      ( irq_sources            ),
        .eip_targets_o      ( irq_o                  ),
        .external_bus_io    ( reg_bus                )
    );
    

///////////////////////////////////////////////////////////////////////////////////////
    // ---------------
    // ROM2_FUSE peripheral
    // It has all the keys in fuse registers.
    // ---------------
    //logic [63:0]                  rom2_addr;
    //logic [64-1:0]                rom2_rdata;
    logic                         rom2_req;
    logic [AxiAddrWidth-1:0]      rom2_addr;
    logic                         rom2_we;
    logic [31:0]                  pkey_loc_o;
    logic [3:0][191:0]            key_reg_out;
    logic [AxiDataWidth-1:0]    rom2_rdata;
    logic [AxiDataWidth-1:0]    rom2_wdata;

 
    axi2mem #(
        .AXI_ID_WIDTH   ( AxiIdWidth          ),
        .AXI_ADDR_WIDTH ( AxiAddrWidth        ),
        .AXI_DATA_WIDTH ( AxiDataWidth        ),
        .AXI_USER_WIDTH ( AxiUserWidth        )
    ) i_axi2rom2 (
        .clk_i  ( clk_i                    ),
        .rst_ni ( rst_ni                   ),
        .slave  ( rom2_fuse                ),
        .req_o  ( rom2_req                 ),
        .we_o   ( rom2_we                  ),
        .addr_o ( rom2_addr                ),
        .be_o   (                          ),
        .data_o ( rom2_wdata               ),
        .data_i ( rom2_rdata               )
    );


    rom2 i_rom2 (
        .clk_i      ( clk_i      ),
        .rst_ni     ( rst_ni     ),
        .req_i      ( rom2_req   ),
        .we_i       ( rom2_we    ),
        .addr_i     ( rom2_addr  ),
        .wdata_i    ( rom2_wdata ),
        .rdata_o    ( rom2_rdata ), // this will go to peripheral
        .secure_reg ( key_reg_out)
    );
    
    assign jtag_key = key_reg_out[1][31:0];
    assign access_ctrl_reg[0] = key_reg_out[2][47:0];
    assign access_ctrl_reg[1] = key_reg_out[3][47:0];


///////////////////////////////////////////////////////////////////////////////////////
    // ---------------
    // 4. pkt.
    // It is the peripheral key table. It will take peripheral id from the apllication and provide location of key in rom2
    // 
    // ---------------

    REG_BUS #(
        .ADDR_WIDTH ( 32 ),
        .DATA_WIDTH ( 32 )
    ) reg_bus_pkt (clk_i);
    
    logic         pkt_penable;
    logic         pkt_pwrite;
    logic [31:0]  pkt_paddr;
    logic         pkt_psel;
    logic [31:0]  pkt_pwdata;
    logic [31:0]  pkt_prdata;
    logic         pkt_pready;
    logic         pkt_pslverr;

    axi2apb_64_32 #(
        .AXI4_ADDRESS_WIDTH ( AxiAddrWidth  ),
        .AXI4_RDATA_WIDTH   ( AxiDataWidth  ),
        .AXI4_WDATA_WIDTH   ( AxiDataWidth  ),
        .AXI4_ID_WIDTH      ( AxiIdWidth    ),
        .AXI4_USER_WIDTH    ( AxiUserWidth  ),
        .BUFF_DEPTH_SLAVE   ( 2             ),
        .APB_ADDR_WIDTH     ( 32            )
    ) i_axi2apb_64_32_pkt (
        .ACLK      ( clk_i          ),
        .ARESETn   ( rst_ni         ),
        .test_en_i ( 1'b0           ),
        .AWID_i    ( pkt.aw_id     ),
        .AWADDR_i  ( pkt.aw_addr   ),
        .AWLEN_i   ( pkt.aw_len    ),
        .AWSIZE_i  ( pkt.aw_size   ),
        .AWBURST_i ( pkt.aw_burst  ),
        .AWLOCK_i  ( pkt.aw_lock   ),
        .AWCACHE_i ( pkt.aw_cache  ),
        .AWPROT_i  ( pkt.aw_prot   ),
        .AWREGION_i( pkt.aw_region ),
        .AWUSER_i  ( pkt.aw_user   ),
        .AWQOS_i   ( pkt.aw_qos    ),
        .AWVALID_i ( pkt.aw_valid  ),
        .AWREADY_o ( pkt.aw_ready  ),
        .WDATA_i   ( pkt.w_data    ),
        .WSTRB_i   ( pkt.w_strb    ),
        .WLAST_i   ( pkt.w_last    ),
        .WUSER_i   ( pkt.w_user    ),
        .WVALID_i  ( pkt.w_valid   ),
        .WREADY_o  ( pkt.w_ready   ),
        .BID_o     ( pkt.b_id      ),
        .BRESP_o   ( pkt.b_resp    ),
        .BVALID_o  ( pkt.b_valid   ),
        .BUSER_o   ( pkt.b_user    ),
        .BREADY_i  ( pkt.b_ready   ),
        .ARID_i    ( pkt.ar_id     ),
        .ARADDR_i  ( pkt.ar_addr   ),
        .ARLEN_i   ( pkt.ar_len    ),
        .ARSIZE_i  ( pkt.ar_size   ),
        .ARBURST_i ( pkt.ar_burst  ),
        .ARLOCK_i  ( pkt.ar_lock   ),
        .ARCACHE_i ( pkt.ar_cache  ),
        .ARPROT_i  ( pkt.ar_prot   ),
        .ARREGION_i( pkt.ar_region ),
        .ARUSER_i  ( pkt.ar_user   ),
        .ARQOS_i   ( pkt.ar_qos    ),
        .ARVALID_i ( pkt.ar_valid  ),
        .ARREADY_o ( pkt.ar_ready  ),
        .RID_o     ( pkt.r_id      ),
        .RDATA_o   ( pkt.r_data    ),
        .RRESP_o   ( pkt.r_resp    ),
        .RLAST_o   ( pkt.r_last    ),
        .RUSER_o   ( pkt.r_user    ),
        .RVALID_o  ( pkt.r_valid   ),
        .RREADY_i  ( pkt.r_ready   ),
        .PENABLE   ( pkt_penable   ),
        .PWRITE    ( pkt_pwrite    ),
        .PADDR     ( pkt_paddr     ),
        .PSEL      ( pkt_psel      ),
        .PWDATA    ( pkt_pwdata    ),
        .PRDATA    ( pkt_prdata    ),
        .PREADY    ( pkt_pready    ),
        .PSLVERR   ( pkt_pslverr   )
    );

    apb_to_reg i_apb_to_reg_pkt (
        .clk_i     ( clk_i        ),
        .rst_ni    ( rst_ni       ),
        .penable_i ( pkt_penable ),
        .pwrite_i  ( pkt_pwrite  ),
        .paddr_i   ( pkt_paddr   ),
        .psel_i    ( pkt_psel    ),
        .pwdata_i  ( pkt_pwdata  ),
        .prdata_o  ( pkt_prdata  ),
        .pready_o  ( pkt_pready  ),
        .pslverr_o ( pkt_pslverr ),
        .reg_o     ( reg_bus_pkt )
    );

    pkt_wrapper #(
    ) i_pkt_wrapper (
        .clk_i              ( clk_i                  ),
        .rst_ni             ( rst_ni                 ),
        .pkey_loc_o         ( pkey_loc_o             ),
        .external_bus_io    ( reg_bus_pkt            )
    );

/////////////////////////////////////////////////////////////////////////////////////////
//    // ---------------
//    // Peripheral Key Table (pkt)
//    // ---------------
//    logic                         pkt_req;
//    logic [AXI_ADDRESS_WIDTH-1:0] pkt_addr;
//    logic [AXI_DATA_WIDTH-1:0]    pkt_rdata;
//
//    axi2mem #(
//        .AXI_ID_WIDTH   ( AXI_ID_WIDTH_SLAVES ),
//        .AXI_ADDR_WIDTH ( AXI_ADDRESS_WIDTH   ),
//        .AXI_DATA_WIDTH ( AXI_DATA_WIDTH      ),
//        .AXI_USER_WIDTH ( AXI_USER_WIDTH      )
//    ) i_axi2pkt (
//        .clk_i  ( clk_i                   ),
//        .rst_ni ( ndmreset_n              ),
//        .slave  ( master[ariane_soc::PKT]),
//        .req_o  ( pkt_req                  ),
//        .we_o   (                         ),
//        .addr_o ( pkt_addr                 ),
//        .be_o   (                         ),
//        .data_o (                         ),
//        .data_i ( pkt_rdata                )
//    );
//
//    pkt i_pkt (
//        .clk_i      ( clk_i     ),
//        .req_i      ( pkt_req   ),
//        .addr_i     ( pkt_addr  ),
//        .pkey_loc_o    ( rom2_addr )
//    );
//
///////////////////////////////////////////////////////////////////////////////////////
//  Interface for AES (Similar to PLIC)

    // ---------------
    // 4. AES
    // ---------------

    REG_BUS #(
        .ADDR_WIDTH ( 32 ),
        .DATA_WIDTH ( 32 )
    ) reg_bus_aes (clk_i);
    
    //logic [191:0] aes_key_in;
    logic         aes_penable;
    logic         aes_pwrite;
    logic [31:0]  aes_paddr;
    logic         aes_psel;
    logic [31:0]  aes_pwdata;
    logic [31:0]  aes_prdata;
    logic         aes_pready;
    logic         aes_pslverr;

    axi2apb_64_32 #(
        .AXI4_ADDRESS_WIDTH ( AxiAddrWidth  ),
        .AXI4_RDATA_WIDTH   ( AxiDataWidth  ),
        .AXI4_WDATA_WIDTH   ( AxiDataWidth  ),
        .AXI4_ID_WIDTH      ( AxiIdWidth    ),
        .AXI4_USER_WIDTH    ( AxiUserWidth  ),
        .BUFF_DEPTH_SLAVE   ( 2             ),
        .APB_ADDR_WIDTH     ( 32            )
    ) i_axi2apb_64_32_aes (
        .ACLK      ( clk_i          ),
        .ARESETn   ( rst_ni         ),
        .test_en_i ( 1'b0           ),
        .AWID_i    ( aes.aw_id     ),
        .AWADDR_i  ( aes.aw_addr   ),
        .AWLEN_i   ( aes.aw_len    ),
        .AWSIZE_i  ( aes.aw_size   ),
        .AWBURST_i ( aes.aw_burst  ),
        .AWLOCK_i  ( aes.aw_lock   ),
        .AWCACHE_i ( aes.aw_cache  ),
        .AWPROT_i  ( aes.aw_prot   ),
        .AWREGION_i( aes.aw_region ),
        .AWUSER_i  ( aes.aw_user   ),
        .AWQOS_i   ( aes.aw_qos    ),
        .AWVALID_i ( aes.aw_valid  ),
        .AWREADY_o ( aes.aw_ready  ),
        .WDATA_i   ( aes.w_data    ),
        .WSTRB_i   ( aes.w_strb    ),
        .WLAST_i   ( aes.w_last    ),
        .WUSER_i   ( aes.w_user    ),
        .WVALID_i  ( aes.w_valid   ),
        .WREADY_o  ( aes.w_ready   ),
        .BID_o     ( aes.b_id      ),
        .BRESP_o   ( aes.b_resp    ),
        .BVALID_o  ( aes.b_valid   ),
        .BUSER_o   ( aes.b_user    ),
        .BREADY_i  ( aes.b_ready   ),
        .ARID_i    ( aes.ar_id     ),
        .ARADDR_i  ( aes.ar_addr   ),
        .ARLEN_i   ( aes.ar_len    ),
        .ARSIZE_i  ( aes.ar_size   ),
        .ARBURST_i ( aes.ar_burst  ),
        .ARLOCK_i  ( aes.ar_lock   ),
        .ARCACHE_i ( aes.ar_cache  ),
        .ARPROT_i  ( aes.ar_prot   ),
        .ARREGION_i( aes.ar_region ),
        .ARUSER_i  ( aes.ar_user   ),
        .ARQOS_i   ( aes.ar_qos    ),
        .ARVALID_i ( aes.ar_valid  ),
        .ARREADY_o ( aes.ar_ready  ),
        .RID_o     ( aes.r_id      ),
        .RDATA_o   ( aes.r_data    ),
        .RRESP_o   ( aes.r_resp    ),
        .RLAST_o   ( aes.r_last    ),
        .RUSER_o   ( aes.r_user    ),
        .RVALID_o  ( aes.r_valid   ),
        .RREADY_i  ( aes.r_ready   ),
        .PENABLE   ( aes_penable   ),
        .PWRITE    ( aes_pwrite    ),
        .PADDR     ( aes_paddr     ),
        .PSEL      ( aes_psel      ),
        .PWDATA    ( aes_pwdata    ),
        .PRDATA    ( aes_prdata    ),
        .PREADY    ( aes_pready    ),
        .PSLVERR   ( aes_pslverr   )
    );

    apb_to_reg i_apb_to_reg_aes (
        .clk_i     ( clk_i        ),
        .rst_ni    ( rst_ni       ),
        .penable_i ( aes_penable ),
        .pwrite_i  ( aes_pwrite  ),
        .paddr_i   ( aes_paddr   ),
        .psel_i    ( aes_psel    ),
        .pwdata_i  ( aes_pwdata  ),
        .prdata_o  ( aes_prdata  ),
        .pready_o  ( aes_pready  ),
        .pslverr_o ( aes_pslverr ),
        .reg_o     ( reg_bus_aes )
    );

    aes_wrapper #(
    ) i_aes_wrapper (
        .clk_i              ( clk_i                  ),
        .rst_ni             ( rst_ni                 ),
        .key_in             (key_reg_out[0]          ),
        .external_bus_io    ( reg_bus_aes            )
    );

///////////////////////////////////////////////////////////////////////////////////////
    // ---------------
    // 2. UART
    // ---------------
    logic         uart_penable;
    logic         uart_pwrite;
    logic [31:0]  uart_paddr;
    logic         uart_psel;
    logic [31:0]  uart_pwdata;
    logic [31:0]  uart_prdata;
    logic         uart_pready;
    logic         uart_pslverr;

    axi2apb_64_32 #(
        .AXI4_ADDRESS_WIDTH ( AxiAddrWidth ),
        .AXI4_RDATA_WIDTH   ( AxiDataWidth ),
        .AXI4_WDATA_WIDTH   ( AxiDataWidth ),
        .AXI4_ID_WIDTH      ( AxiIdWidth   ),
        .AXI4_USER_WIDTH    ( AxiUserWidth ),
        .BUFF_DEPTH_SLAVE   ( 2            ),
        .APB_ADDR_WIDTH     ( 32           )
    ) i_axi2apb_64_32_uart (
        .ACLK      ( clk_i          ),
        .ARESETn   ( rst_ni         ),
        .test_en_i ( 1'b0           ),
        .AWID_i    ( uart.aw_id     ),
        .AWADDR_i  ( uart.aw_addr   ),
        .AWLEN_i   ( uart.aw_len    ),
        .AWSIZE_i  ( uart.aw_size   ),
        .AWBURST_i ( uart.aw_burst  ),
        .AWLOCK_i  ( uart.aw_lock   ),
        .AWCACHE_i ( uart.aw_cache  ),
        .AWPROT_i  ( uart.aw_prot   ),
        .AWREGION_i( uart.aw_region ),
        .AWUSER_i  ( uart.aw_user   ),
        .AWQOS_i   ( uart.aw_qos    ),
        .AWVALID_i ( uart.aw_valid  ),
        .AWREADY_o ( uart.aw_ready  ),
        .WDATA_i   ( uart.w_data    ),
        .WSTRB_i   ( uart.w_strb    ),
        .WLAST_i   ( uart.w_last    ),
        .WUSER_i   ( uart.w_user    ),
        .WVALID_i  ( uart.w_valid   ),
        .WREADY_o  ( uart.w_ready   ),
        .BID_o     ( uart.b_id      ),
        .BRESP_o   ( uart.b_resp    ),
        .BVALID_o  ( uart.b_valid   ),
        .BUSER_o   ( uart.b_user    ),
        .BREADY_i  ( uart.b_ready   ),
        .ARID_i    ( uart.ar_id     ),
        .ARADDR_i  ( uart.ar_addr   ),
        .ARLEN_i   ( uart.ar_len    ),
        .ARSIZE_i  ( uart.ar_size   ),
        .ARBURST_i ( uart.ar_burst  ),
        .ARLOCK_i  ( uart.ar_lock   ),
        .ARCACHE_i ( uart.ar_cache  ),
        .ARPROT_i  ( uart.ar_prot   ),
        .ARREGION_i( uart.ar_region ),
        .ARUSER_i  ( uart.ar_user   ),
        .ARQOS_i   ( uart.ar_qos    ),
        .ARVALID_i ( uart.ar_valid  ),
        .ARREADY_o ( uart.ar_ready  ),
        .RID_o     ( uart.r_id      ),
        .RDATA_o   ( uart.r_data    ),
        .RRESP_o   ( uart.r_resp    ),
        .RLAST_o   ( uart.r_last    ),
        .RUSER_o   ( uart.r_user    ),
        .RVALID_o  ( uart.r_valid   ),
        .RREADY_i  ( uart.r_ready   ),
        .PENABLE   ( uart_penable   ),
        .PWRITE    ( uart_pwrite    ),
        .PADDR     ( uart_paddr     ),
        .PSEL      ( uart_psel      ),
        .PWDATA    ( uart_pwdata    ),
        .PRDATA    ( uart_prdata    ),
        .PREADY    ( uart_pready    ),
        .PSLVERR   ( uart_pslverr   )
    );

    if (InclUART) begin : gen_uart
        apb_uart i_apb_uart (
            .CLK     ( clk_i           ),
            .RSTN    ( rst_ni          ),
            .PSEL    ( uart_psel       ),
            .PENABLE ( uart_penable    ),
            .PWRITE  ( uart_pwrite     ),
            .PADDR   ( uart_paddr[4:2] ),
            .PWDATA  ( uart_pwdata     ),
            .PRDATA  ( uart_prdata     ),
            .PREADY  ( uart_pready     ),
            .PSLVERR ( uart_pslverr    ),
            .INT     ( irq_sources[2]  ),
            .OUT1N   (                 ), // keep open
            .OUT2N   (                 ), // keep open
            .RTSN    (                 ), // no flow control
            .DTRN    (                 ), // no flow control
            .CTSN    ( 1'b0            ),
            .DSRN    ( 1'b0            ),
            .DCDN    ( 1'b0            ),
            .RIN     ( 1'b0            ),
            .SIN     ( rx_i            ),
            .SOUT    ( tx_o            )
        );
    end else begin
        /* pragma translate_off */
        `ifndef VERILATOR
        mock_uart i_mock_uart (
            .clk_i     ( clk_i        ),
            .rst_ni    ( rst_ni       ),
            .penable_i ( uart_penable ),
            .pwrite_i  ( uart_pwrite  ),
            .paddr_i   ( uart_paddr   ),
            .psel_i    ( uart_psel    ),
            .pwdata_i  ( uart_pwdata  ),
            .prdata_o  ( uart_prdata  ),
            .pready_o  ( uart_pready  ),
            .pslverr_o ( uart_pslverr )
        );
        `endif
        /* pragma translate_on */
    end

    // ---------------
    // 3. SPI
    // ---------------
    if (InclSPI) begin : gen_spi
        logic [31:0] s_axi_spi_awaddr;
        logic [7:0]  s_axi_spi_awlen;
        logic [2:0]  s_axi_spi_awsize;
        logic [1:0]  s_axi_spi_awburst;
        logic [0:0]  s_axi_spi_awlock;
        logic [3:0]  s_axi_spi_awcache;
        logic [2:0]  s_axi_spi_awprot;
        logic [3:0]  s_axi_spi_awregion;
        logic [3:0]  s_axi_spi_awqos;
        logic        s_axi_spi_awvalid;
        logic        s_axi_spi_awready;
        logic [31:0] s_axi_spi_wdata;
        logic [3:0]  s_axi_spi_wstrb;
        logic        s_axi_spi_wlast;
        logic        s_axi_spi_wvalid;
        logic        s_axi_spi_wready;
        logic [1:0]  s_axi_spi_bresp;
        logic        s_axi_spi_bvalid;
        logic        s_axi_spi_bready;
        logic [31:0] s_axi_spi_araddr;
        logic [7:0]  s_axi_spi_arlen;
        logic [2:0]  s_axi_spi_arsize;
        logic [1:0]  s_axi_spi_arburst;
        logic [0:0]  s_axi_spi_arlock;
        logic [3:0]  s_axi_spi_arcache;
        logic [2:0]  s_axi_spi_arprot;
        logic [3:0]  s_axi_spi_arregion;
        logic [3:0]  s_axi_spi_arqos;
        logic        s_axi_spi_arvalid;
        logic        s_axi_spi_arready;
        logic [31:0] s_axi_spi_rdata;
        logic [1:0]  s_axi_spi_rresp;
        logic        s_axi_spi_rlast;
        logic        s_axi_spi_rvalid;
        logic        s_axi_spi_rready;

        xlnx_axi_clock_converter i_xlnx_axi_clock_converter_spi (
            .s_axi_aclk     ( clk_i              ),
            .s_axi_aresetn  ( rst_ni             ),

            .s_axi_awid     ( spi.aw_id          ),
            .s_axi_awaddr   ( spi.aw_addr[31:0]  ),
            .s_axi_awlen    ( spi.aw_len         ),
            .s_axi_awsize   ( spi.aw_size        ),
            .s_axi_awburst  ( spi.aw_burst       ),
            .s_axi_awlock   ( spi.aw_lock        ),
            .s_axi_awcache  ( spi.aw_cache       ),
            .s_axi_awprot   ( spi.aw_prot        ),
            .s_axi_awregion ( spi.aw_region      ),
            .s_axi_awqos    ( spi.aw_qos         ),
            .s_axi_awvalid  ( spi.aw_valid       ),
            .s_axi_awready  ( spi.aw_ready       ),
            .s_axi_wdata    ( spi.w_data         ),
            .s_axi_wstrb    ( spi.w_strb         ),
            .s_axi_wlast    ( spi.w_last         ),
            .s_axi_wvalid   ( spi.w_valid        ),
            .s_axi_wready   ( spi.w_ready        ),
            .s_axi_bid      ( spi.b_id           ),
            .s_axi_bresp    ( spi.b_resp         ),
            .s_axi_bvalid   ( spi.b_valid        ),
            .s_axi_bready   ( spi.b_ready        ),
            .s_axi_arid     ( spi.ar_id          ),
            .s_axi_araddr   ( spi.ar_addr[31:0]  ),
            .s_axi_arlen    ( spi.ar_len         ),
            .s_axi_arsize   ( spi.ar_size        ),
            .s_axi_arburst  ( spi.ar_burst       ),
            .s_axi_arlock   ( spi.ar_lock        ),
            .s_axi_arcache  ( spi.ar_cache       ),
            .s_axi_arprot   ( spi.ar_prot        ),
            .s_axi_arregion ( spi.ar_region      ),
            .s_axi_arqos    ( spi.ar_qos         ),
            .s_axi_arvalid  ( spi.ar_valid       ),
            .s_axi_arready  ( spi.ar_ready       ),
            .s_axi_rid      ( spi.r_id           ),
            .s_axi_rdata    ( spi.r_data         ),
            .s_axi_rresp    ( spi.r_resp         ),
            .s_axi_rlast    ( spi.r_last         ),
            .s_axi_rvalid   ( spi.r_valid        ),
            .s_axi_rready   ( spi.r_ready        ),

            .m_axi_awaddr   ( s_axi_spi_awaddr   ),
            .m_axi_awlen    ( s_axi_spi_awlen    ),
            .m_axi_awsize   ( s_axi_spi_awsize   ),
            .m_axi_awburst  ( s_axi_spi_awburst  ),
            .m_axi_awlock   ( s_axi_spi_awlock   ),
            .m_axi_awcache  ( s_axi_spi_awcache  ),
            .m_axi_awprot   ( s_axi_spi_awprot   ),
            .m_axi_awregion ( s_axi_spi_awregion ),
            .m_axi_awqos    ( s_axi_spi_awqos    ),
            .m_axi_awvalid  ( s_axi_spi_awvalid  ),
            .m_axi_awready  ( s_axi_spi_awready  ),
            .m_axi_wdata    ( s_axi_spi_wdata    ),
            .m_axi_wstrb    ( s_axi_spi_wstrb    ),
            .m_axi_wlast    ( s_axi_spi_wlast    ),
            .m_axi_wvalid   ( s_axi_spi_wvalid   ),
            .m_axi_wready   ( s_axi_spi_wready   ),
            .m_axi_bresp    ( s_axi_spi_bresp    ),
            .m_axi_bvalid   ( s_axi_spi_bvalid   ),
            .m_axi_bready   ( s_axi_spi_bready   ),
            .m_axi_araddr   ( s_axi_spi_araddr   ),
            .m_axi_arlen    ( s_axi_spi_arlen    ),
            .m_axi_arsize   ( s_axi_spi_arsize   ),
            .m_axi_arburst  ( s_axi_spi_arburst  ),
            .m_axi_arlock   ( s_axi_spi_arlock   ),
            .m_axi_arcache  ( s_axi_spi_arcache  ),
            .m_axi_arprot   ( s_axi_spi_arprot   ),
            .m_axi_arregion ( s_axi_spi_arregion ),
            .m_axi_arqos    ( s_axi_spi_arqos    ),
            .m_axi_arvalid  ( s_axi_spi_arvalid  ),
            .m_axi_arready  ( s_axi_spi_arready  ),
            .m_axi_rdata    ( s_axi_spi_rdata    ),
            .m_axi_rresp    ( s_axi_spi_rresp    ),
            .m_axi_rlast    ( s_axi_spi_rlast    ),
            .m_axi_rvalid   ( s_axi_spi_rvalid   ),
            .m_axi_rready   ( s_axi_spi_rready   )
        );

        xlnx_axi_quad_spi i_xlnx_axi_quad_spi (
            .ext_spi_clk    ( clk_i                  ),
            .s_axi4_aclk    ( clk_i                  ),
            .s_axi4_aresetn ( rst_ni                 ),
            .s_axi4_awaddr  ( s_axi_spi_awaddr[23:0] ),
            .s_axi4_awlen   ( s_axi_spi_awlen        ),
            .s_axi4_awsize  ( s_axi_spi_awsize       ),
            .s_axi4_awburst ( s_axi_spi_awburst      ),
            .s_axi4_awlock  ( s_axi_spi_awlock       ),
            .s_axi4_awcache ( s_axi_spi_awcache      ),
            .s_axi4_awprot  ( s_axi_spi_awprot       ),
            .s_axi4_awvalid ( s_axi_spi_awvalid      ),
            .s_axi4_awready ( s_axi_spi_awready      ),
            .s_axi4_wdata   ( s_axi_spi_wdata        ),
            .s_axi4_wstrb   ( s_axi_spi_wstrb        ),
            .s_axi4_wlast   ( s_axi_spi_wlast        ),
            .s_axi4_wvalid  ( s_axi_spi_wvalid       ),
            .s_axi4_wready  ( s_axi_spi_wready       ),
            .s_axi4_bresp   ( s_axi_spi_bresp        ),
            .s_axi4_bvalid  ( s_axi_spi_bvalid       ),
            .s_axi4_bready  ( s_axi_spi_bready       ),
            .s_axi4_araddr  ( s_axi_spi_araddr[23:0] ),
            .s_axi4_arlen   ( s_axi_spi_arlen        ),
            .s_axi4_arsize  ( s_axi_spi_arsize       ),
            .s_axi4_arburst ( s_axi_spi_arburst      ),
            .s_axi4_arlock  ( s_axi_spi_arlock       ),
            .s_axi4_arcache ( s_axi_spi_arcache      ),
            .s_axi4_arprot  ( s_axi_spi_arprot       ),
            .s_axi4_arvalid ( s_axi_spi_arvalid      ),
            .s_axi4_arready ( s_axi_spi_arready      ),
            .s_axi4_rdata   ( s_axi_spi_rdata        ),
            .s_axi4_rresp   ( s_axi_spi_rresp        ),
            .s_axi4_rlast   ( s_axi_spi_rlast        ),
            .s_axi4_rvalid  ( s_axi_spi_rvalid       ),
            .s_axi4_rready  ( s_axi_spi_rready       ),

            .io0_i          ( '0                     ),
            .io0_o          ( spi_mosi               ),
            .io0_t          ( '0                     ),
            .io1_i          ( spi_miso               ),
            .io1_o          (                        ),
            .io1_t          ( '0                     ),
            .ss_i           ( '0                     ),
            .ss_o           ( spi_ss                 ),
            .ss_t           ( '0                     ),
            .sck_o          ( spi_clk_o              ),
            .sck_i          ( '0                     ),
            .sck_t          (                        ),
            .ip2intc_irpt   ( irq_sources[1]         )
            // .ip2intc_irpt   ( irq_sources[1]         )
        );
        // assign irq_sources [1] = 1'b0;
    end else begin
        assign spi_clk_o = 1'b0;
        assign spi_mosi = 1'b0;
        assign spi_ss = 1'b0;

        assign irq_sources [1] = 1'b0;
        assign spi.aw_ready = 1'b1;
        assign spi.ar_ready = 1'b1;
        assign spi.w_ready = 1'b1;

        assign spi.b_valid = spi.aw_valid;
        assign spi.b_id = spi.aw_id;
        assign spi.b_resp = axi_pkg::RESP_SLVERR;
        assign spi.b_user = '0;

        assign spi.r_valid = spi.ar_valid;
        assign spi.r_resp = axi_pkg::RESP_SLVERR;
        assign spi.r_data = 'hdeadbeef;
        assign spi.r_last = 1'b1;
    end


    // ---------------
    // 4. Ethernet
    // ---------------
    if (InclEthernet) begin : gen_ethernet
        wire         mdio_i, mdio_o, mdio_t;
        logic [3:0]  s_axi_eth_awid;
        logic [31:0] s_axi_eth_awaddr;
        logic [7:0]  s_axi_eth_awlen;
        logic [2:0]  s_axi_eth_awsize;
        logic [1:0]  s_axi_eth_awburst;
        logic [3:0]  s_axi_eth_awcache;
        logic        s_axi_eth_awvalid;
        logic        s_axi_eth_awready;
        logic [31:0] s_axi_eth_wdata;
        logic [3:0]  s_axi_eth_wstrb;
        logic        s_axi_eth_wlast;
        logic        s_axi_eth_wvalid;
        logic        s_axi_eth_wready;
        logic [3:0]  s_axi_eth_bid;
        logic [1:0]  s_axi_eth_bresp;
        logic        s_axi_eth_bvalid;
        logic        s_axi_eth_bready;
        logic [3:0]  s_axi_eth_arid;
        logic [31:0] s_axi_eth_araddr;
        logic [7:0]  s_axi_eth_arlen;
        logic [2:0]  s_axi_eth_arsize;
        logic [1:0]  s_axi_eth_arburst;
        logic [3:0]  s_axi_eth_arcache;
        logic        s_axi_eth_arvalid;
        logic        s_axi_eth_arready;
        logic [3:0]  s_axi_eth_rid;
        logic [31:0] s_axi_eth_rdata;
        logic [1:0]  s_axi_eth_rresp;
        logic        s_axi_eth_rlast;
        logic        s_axi_eth_rvalid;

        assign s_axi_eth_awid = '0;
        assign s_axi_eth_arid = '0;

        // system-bus is 64-bit, convert down to 32 bit
        xlnx_axi_clock_converter i_xlnx_axi_clock_converter_ethernet (
            .s_axi_aclk     ( clk_i                  ),
            .s_axi_aresetn  ( rst_ni                 ),
            .s_axi_awid     ( ethernet.aw_id         ),
            .s_axi_awaddr   ( ethernet.aw_addr[31:0] ),
            .s_axi_awlen    ( ethernet.aw_len        ),
            .s_axi_awsize   ( ethernet.aw_size       ),
            .s_axi_awburst  ( ethernet.aw_burst      ),
            .s_axi_awlock   ( ethernet.aw_lock       ),
            .s_axi_awcache  ( ethernet.aw_cache      ),
            .s_axi_awprot   ( ethernet.aw_prot       ),
            .s_axi_awregion ( ethernet.aw_region     ),
            .s_axi_awqos    ( ethernet.aw_qos        ),
            .s_axi_awvalid  ( ethernet.aw_valid      ),
            .s_axi_awready  ( ethernet.aw_ready      ),
            .s_axi_wdata    ( ethernet.w_data        ),
            .s_axi_wstrb    ( ethernet.w_strb        ),
            .s_axi_wlast    ( ethernet.w_last        ),
            .s_axi_wvalid   ( ethernet.w_valid       ),
            .s_axi_wready   ( ethernet.w_ready       ),
            .s_axi_bid      ( ethernet.b_id          ),
            .s_axi_bresp    ( ethernet.b_resp        ),
            .s_axi_bvalid   ( ethernet.b_valid       ),
            .s_axi_bready   ( ethernet.b_ready       ),
            .s_axi_arid     ( ethernet.ar_id         ),
            .s_axi_araddr   ( ethernet.ar_addr[31:0] ),
            .s_axi_arlen    ( ethernet.ar_len        ),
            .s_axi_arsize   ( ethernet.ar_size       ),
            .s_axi_arburst  ( ethernet.ar_burst      ),
            .s_axi_arlock   ( ethernet.ar_lock       ),
            .s_axi_arcache  ( ethernet.ar_cache      ),
            .s_axi_arprot   ( ethernet.ar_prot       ),
            .s_axi_arregion ( ethernet.ar_region     ),
            .s_axi_arqos    ( ethernet.ar_qos        ),
            .s_axi_arvalid  ( ethernet.ar_valid      ),
            .s_axi_arready  ( ethernet.ar_ready      ),
            .s_axi_rid      ( ethernet.r_id          ),
            .s_axi_rdata    ( ethernet.r_data        ),
            .s_axi_rresp    ( ethernet.r_resp        ),
            .s_axi_rlast    ( ethernet.r_last        ),
            .s_axi_rvalid   ( ethernet.r_valid       ),
            .s_axi_rready   ( ethernet.r_ready       ),

            .m_axi_awaddr   ( s_axi_eth_awaddr  ),
            .m_axi_awlen    ( s_axi_eth_awlen   ),
            .m_axi_awsize   ( s_axi_eth_awsize  ),
            .m_axi_awburst  ( s_axi_eth_awburst ),
            .m_axi_awlock   (                   ),
            .m_axi_awcache  ( s_axi_eth_awcache ),
            .m_axi_awprot   (                   ),
            .m_axi_awregion (                   ),
            .m_axi_awqos    (                   ),
            .m_axi_awvalid  ( s_axi_eth_awvalid ),
            .m_axi_awready  ( s_axi_eth_awready ),
            .m_axi_wdata    ( s_axi_eth_wdata   ),
            .m_axi_wstrb    ( s_axi_eth_wstrb   ),
            .m_axi_wlast    ( s_axi_eth_wlast   ),
            .m_axi_wvalid   ( s_axi_eth_wvalid  ),
            .m_axi_wready   ( s_axi_eth_wready  ),
            .m_axi_bresp    ( s_axi_eth_bresp   ),
            .m_axi_bvalid   ( s_axi_eth_bvalid  ),
            .m_axi_bready   ( s_axi_eth_bready  ),
            .m_axi_araddr   ( s_axi_eth_araddr  ),
            .m_axi_arlen    ( s_axi_eth_arlen   ),
            .m_axi_arsize   ( s_axi_eth_arsize  ),
            .m_axi_arburst  ( s_axi_eth_arburst ),
            .m_axi_arlock   (                   ),
            .m_axi_arcache  ( s_axi_eth_arcache ),
            .m_axi_arprot   (                   ),
            .m_axi_arregion (                   ),
            .m_axi_arqos    (                   ),
            .m_axi_arvalid  ( s_axi_eth_arvalid ),
            .m_axi_arready  ( s_axi_eth_arready ),
            .m_axi_rdata    ( s_axi_eth_rdata   ),
            .m_axi_rresp    ( s_axi_eth_rresp   ),
            .m_axi_rlast    ( s_axi_eth_rlast   ),
            .m_axi_rvalid   ( s_axi_eth_rvalid  ),
            .m_axi_rready   ( m_axi_rready      )
        );

        xlnx_axi_ethernetlite i_xlnx_axi_ethernetlite (
            .s_axi_aclk    ( clk_i                   ),
            .s_axi_aresetn ( rst_ni                  ),
            .ip2intc_irpt  ( irq_sources[0]          ),
            .s_axi_awid    ( s_axi_eth_awid          ),
            .s_axi_awaddr  ( s_axi_eth_awaddr[12:0]  ),
            .s_axi_awlen   ( s_axi_eth_awlen         ),
            .s_axi_awsize  ( s_axi_eth_awsize        ),
            .s_axi_awburst ( s_axi_eth_awburst       ),
            .s_axi_awcache ( s_axi_eth_awcache       ),
            .s_axi_awvalid ( s_axi_eth_awvalid       ),
            .s_axi_awready ( s_axi_eth_awready       ),
            .s_axi_wdata   ( s_axi_eth_wdata         ),
            .s_axi_wstrb   ( s_axi_eth_wstrb         ),
            .s_axi_wlast   ( s_axi_eth_wlast         ),
            .s_axi_wvalid  ( s_axi_eth_wvalid        ),
            .s_axi_wready  ( s_axi_eth_wready        ),
            .s_axi_bid     ( s_axi_eth_bid           ),
            .s_axi_bresp   ( s_axi_eth_bresp         ),
            .s_axi_bvalid  ( s_axi_eth_bvalid        ),
            .s_axi_bready  ( s_axi_eth_bready        ),
            .s_axi_arid    ( s_axi_eth_arid          ),
            .s_axi_araddr  ( s_axi_eth_araddr[12:0]  ),
            .s_axi_arlen   ( s_axi_eth_arlen         ),
            .s_axi_arsize  ( s_axi_eth_arsize        ),
            .s_axi_arburst ( s_axi_eth_arburst       ),
            .s_axi_arcache ( s_axi_eth_arcache       ),
            .s_axi_arvalid ( s_axi_eth_arvalid       ),
            .s_axi_arready ( s_axi_eth_arready       ),
            .s_axi_rid     ( s_axi_eth_rid           ),
            .s_axi_rdata   ( s_axi_eth_rdata         ),
            .s_axi_rresp   ( s_axi_eth_rresp         ),
            .s_axi_rlast   ( s_axi_eth_rlast         ),
            .s_axi_rvalid  ( s_axi_eth_rvalid        ),
            .s_axi_rready  ( s_axi_eth_rready        ),
            .phy_tx_clk    ( eth_txck                ),
            .phy_rx_clk    ( eth_rxck                ),
            .phy_crs       ( 1'b0                    ),
            .phy_dv        ( eth_rxctl               ),
            .phy_rx_data   ( eth_rxd                 ),
            .phy_col       ( 1'b0                    ),
            .phy_rx_er     ( 1'b0                    ),
            .phy_rst_n     ( eth_rst_n               ),
            .phy_tx_en     ( eth_tx_en               ),
            .phy_tx_data   ( eth_txd                 ),
            .phy_mdio_i    ( mdio_i                  ),
            .phy_mdio_o    ( mdio_o                  ),
            .phy_mdio_t    ( mdio_t                  ),
            .phy_mdc       ( eth_mdc                 )
        );
        IOBUF mdio_io_iobuf (.I (mdio_o), .IO(mdio), .O (mdio_i), .T (mdio_t));
    end else begin
        assign irq_sources [2] = 1'b0;
        assign ethernet.aw_ready = 1'b1;
        assign ethernet.ar_ready = 1'b1;
        assign ethernet.w_ready = 1'b1;

        assign ethernet.b_valid = ethernet.aw_valid;
        assign ethernet.b_id = ethernet.aw_id;
        assign ethernet.b_resp = axi_pkg::RESP_SLVERR;
        assign ethernet.b_user = '0;

        assign ethernet.r_valid = ethernet.ar_valid;
        assign ethernet.r_resp = axi_pkg::RESP_SLVERR;
        assign ethernet.r_data = 'hdeadbeef;
        assign ethernet.r_last = 1'b1;
    end
endmodule
