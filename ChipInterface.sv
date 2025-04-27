`default_nettype none

module chipInterface (
    input logic CLOCK_50,
    input logic [3:0] KEY,
	 output logic [9:0] LEDR,
    inout logic [35:0] GPIO_0
);

    logic clock, reset;
    assign clock = CLOCK_50;

    logic send;

    Synchronizer syncrst(.sync(reset), .async(~KEY[0]), .clock);
    Synchronizer syncsend(.sync(send), .async(~KEY[1]), .clock);
	 
	 tri1 sda, scl;

    assign sda = GPIO_0[10];
    assign scl = GPIO_0[11];

    logic done, error;

    I2C i2c(.clock, .reset, .send_hello(send), .done, .error, .sda, .scl);
endmodule : chipInterface

// DFlipFlop used for the synchronizer
module DFlipFlop (
    output logic Q,
    input logic D, clock, reset_L, preset_L);

    always_ff @( posedge clock, negedge reset_L, negedge preset_L )
        if ( reset_L == 1'b0 )
            Q <= 0;
        else if (preset_L == 1'b0)
            Q <= 1;
        else
            Q <= D;
endmodule: DFlipFlop

// Synchronizer used to synchronize inputs
module Synchronizer
    #(parameter WIDTH = 16)
    (output logic sync,
     input logic async, clock);

    logic async2;

    DFlipFlop ff1(.D(async), .Q(async2), .clock,
                  .preset_L(1'b1), .reset_L(1'b1));
    DFlipFlop ff2(.D(async2), .Q(sync), .clock,
                  .preset_L(1'b1), .reset_L(1'b1));
endmodule : Synchronizer


