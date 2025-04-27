`default_nettype none

module I2C_test ();
    logic clock, reset, send_hello, done;
    tri1 sda, scl;

    I2C dut(.clock, .reset, .send_hello, .done, .sda, .scl);

    initial begin
        clock = 0;
        forever #5 clock = ~clock;
    end

    initial begin
        reset <= 1'b0;
        send_hello <= 1'b0;
        @(posedge clock);
        reset <= 1'b1;
        @(posedge clock);
        reset <= 1'b0;
        send_hello <= 1'b1;
        @(posedge clock);
        send_hello <= 1'b0;
        wait (done);
        @(posedge clock);
        $finish();
    end
endmodule : I2C_test
