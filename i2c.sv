`default_nettype none

`define LCD_ADDR 7'h72
// Comining the LCD_ADDR with the R/W bit
`define ADDR_BYTE 8'hE4
// LCD recognizes the next data byte as a command
`define CMD 8'h7C
`define CLEAR 8'h2D
// 500 cycles will make the clock 100kHz which is the i2c standard
`define CYCLE_END 16'd500
`define RISE 16'd125
`define FALL 16'd375

module SendByte(
    input logic clock, reset,
    input logic start,
    input logic [7:0] data,
    output logic done, error,
    // use tri1 because sda and scl are pulled up to VCC
    inout tri1 sda, scl
);

    logic [15:0] cycles;
    logic [3:0] bit_idx;
    logic sda_en, scl_en;
    logic sda_val, scl_val;

    logic wait_ack;
    assign wait_ack = bit_idx == 4'h8;
    assign done = bit_idx == 4'd9;

    // Make sure sda and scl are released if not enabled
    assign sda = sda_en ? sda_val : 1'bz;
    assign scl = scl_en ? scl_val : 1'bz;

    logic waiting, sending, is_nak;

    assign error = done & is_nak;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cycles <= 16'h0;
            bit_idx <= 4'h0;
            sda_en <= 1'b0;
            sda_val <= 1'b0;
            scl_en <= 1'b0;
            scl_val <= 1'b0;
            is_nak <= 1'b0;
            sending <= 1'b0;
            waiting <= 1'b0;
        end else begin
            if (sending) begin
                cycles <= cycles + 1;
                if (done) begin
                    cycles <= 16'h0;
                    bit_idx <= 4'h0;
                    sda_val <= 1'b0;
                    scl_val <= 1'b0;
                    is_nak <= 1'b0;
                    sending <= 1'b0;
                    if (start) begin
                        waiting <= 1'b1;
                        sda_en <= 1'b1;
                        scl_en <= 1'b1;
                    end else begin
                        waiting <= 1'b0;
                        sda_en <= 1'b0;
                        scl_en <= 1'b0;
                    end
                end else begin
                    scl_en <= 1'b1;
                    // The HIGH of SCL is in the middle, so that
                    // we know SDA is stable on the rising and falling
                    // edge of SCL
                    if (cycles < `RISE) begin
                        scl_val <= 1'b0;
                    end else if (cycles < `FALL) begin
                        scl_val <= 1'b1;
                    end else if (cycles < `CYCLE_END) begin
                        scl_val <= 1'b0;
                    end else begin
                        cycles <= 16'h0;
                        bit_idx <= bit_idx + 1;
                    end
                    if (~wait_ack) begin
                        sda_en <= 1'b1;
                        // MSB so decrement data idx
                        sda_val <= data[4'h7 - bit_idx];
                    end else begin
                        sda_en <= 1'b0;
                        // If SDA is HIGH in ACK, it is a NAK
                        if (scl_val & sda) begin
                            is_nak <= 1'b1;
                        end
                    end
                end
            end else if (waiting) begin
                // Wait a little bit for the slave to get ready
                if (cycles < `CYCLE_END) begin
                    sda_val <= 1'b0;
                end else begin
                    sda_val <= data[4'h7 - bit_idx];
                end
                if (cycles < 16'd1000) begin
                    scl_en <= 1'b1;
                    scl_val <= 1'b0;
                    cycles <= cycles + 1;
                end else begin
                    scl_en <= 1'b0;
                end
                // Wait until SCL is released (waiting for slave)
                if (scl & (cycles == 16'd1000)) begin
                    waiting <= 1'b0;
                    sending <= 1'b1;
                    cycles <= `RISE;
                end
            end else begin
                if (start) begin
                    waiting <= 1'b1;
                    sda_en <= 1'b1;
                    sda_val <= 1'b0;
                    scl_en <= 1'b1;
                    scl_val <= 1'b0;
                end
            end
        end
    end
endmodule : SendByte

// Sends the address byte, CMD byte and CLR byte
module SendClear (
    input logic clock, reset,
    input logic start,
    output logic done, error,
    inout tri1 sda, scl
);

    logic [15:0] cycles;
    logic start_bit, sending, stop_bit;

    logic sda_en, scl_en;
    logic sda_val, scl_val;

    assign done = stop_bit & (cycles == `RISE);
    assign error = 1'b0;

    assign sda = sda_en ? sda_val : 1'bz;
    assign scl = scl_en ? scl_val : 1'bz;

    logic start_send;
    logic finished_send;

    logic [2:0][7:0] bytes;
    logic [7:0] byte_send;
    logic [3:0] byte_idx;
    // Iterate from the highest to lowest to send all bytes
    assign bytes = {`ADDR_BYTE, `CMD, `CLEAR};

    SendByte sb(.clock, .reset, .start(start_send), .data(byte_send),
                     .done(finished_send), .error(), .sda, .scl);

    assign start_send = sending & (byte_idx != 4'h0);
    assign byte_send = bytes[byte_idx];

    logic buffer;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cycles <= 16'h0;
            start_bit <= 1'b0;
            sending <= 1'b0;
            stop_bit <= 1'b0;
            sda_en <= 1'b0;
            scl_en <= 1'b0;
            sda_val <= 1'b0;
            scl_val <= 1'b0;
            byte_idx <= 4'h2;
        end else begin
            if (start_bit) begin
                cycles <= cycles + 1;
                // Wait a little bit to pull SCL down
                // because SDA needs to be pulled down first
                if (cycles < `RISE) begin
                    sda_en <= 1'b1;
                    sda_val <= 1'b0;
                    scl_en <= 1'b0;
                end else if (cycles == `RISE) begin
                    start_bit <= 1'b0;
                    sending <= 1'b1;
                    cycles <= 16'h0;
                    byte_idx <= 4'h2;
                end
            end else if (sending) begin
                // Disable SDA and SCL because SendByte will enable them
                sda_en <= 1'b0;
                scl_en <= 1'b0;
                if (finished_send) begin
                    if (byte_idx == 4'h0) begin
                        sending <= 1'b0;
                        scl_en <= 1'b1;
                        scl_val <= 1'b0;
                        buffer <= 1'b1;
                        cycles <= 16'h0;
                    end else begin
                        byte_idx <= byte_idx - 4'h1;
                    end
                end
            end else if (buffer) begin
                // Wait a little bit before sending the stop condition
                cycles <= cycles + 1;
                if (cycles < 16'd1000) begin
                    scl_en <= 1'b1;
                    sda_en <= 1'b1;
                    scl_val <= 1'b0;
                    sda_val <= 1'b0;
                end else if (cycles == 16'd1000) begin
                    scl_en <= 1'b0;
                    scl_val <= 1'b0;
                    buffer <= 1'b0;
                    stop_bit <= 1'b1;
                    cycles <= 16'h0;
                end
            end else if (stop_bit) begin
                // Wait until SCL is high (slave wait mechanism)
                if (scl) begin
                    cycles <= cycles + 1;
                    // Wait a little bit before releasing SDA
                    // because SCL needs to be released first
                    if (cycles < `RISE) begin
                        sda_en <= 1'b1;
                        sda_val <= 1'b0;
                    end else if (cycles == `RISE) begin
                        sda_en <= 1'b0;
                        sda_val <= 1'b0;
                        stop_bit <= 1'b0;
                        cycles <= 16'h0;
                    end
                end
            end else begin
                if (start) begin
                    start_bit <= 1'b1;
                end
            end
        end
    end
endmodule : SendClear

// Sends Address byte, H, E, L, L, O
// Same code as SendClear
module SendHello (
    input logic clock, reset,
    input logic start,
    output logic done, error,
    inout tri1 sda, scl
);

    logic [15:0] cycles;
    logic start_bit, sending, stop_bit;

    logic sda_en, scl_en;
    logic sda_val, scl_val;

    assign done = stop_bit & (cycles == `RISE);
    assign error = 1'b0;

    assign sda = sda_en ? sda_val : 1'bz;
    assign scl = scl_en ? scl_val : 1'bz;

    logic start_send;
    logic finished_send;

    logic [5:0][7:0] bytes;
    logic [7:0] byte_send;
    logic [3:0] byte_idx;
    assign bytes = {`ADDR_BYTE, 8'h48, 8'h45, 8'h4C, 8'h4C, 8'h4F};

    SendByte sb(.clock, .reset, .start(start_send), .data(byte_send),
                     .done(finished_send), .error(), .sda, .scl);

    assign start_send = sending & (byte_idx != 0);
    assign byte_send = bytes[byte_idx];

    logic buffer;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            cycles <= 16'h0;
            start_bit <= 1'b0;
            sending <= 1'b0;
            stop_bit <= 1'b0;
            sda_en <= 1'b0;
            scl_en <= 1'b0;
            sda_val <= 1'b0;
            scl_val <= 1'b0;
            byte_idx <= 4'h5;
        end else begin
            if (start_bit) begin
                cycles <= cycles + 1;
                if (cycles < `RISE) begin
                    sda_en <= 1'b1;
                    sda_val <= 1'b0;
                    scl_en <= 1'b0;
                end else if (cycles == `RISE) begin
                    start_bit <= 1'b0;
                    sending <= 1'b1;
                    cycles <= 16'h0;
                    byte_idx <= 4'h5;
                end
            end else if (sending) begin
                sda_en <= 1'b0;
                scl_en <= 1'b0;
                if (finished_send) begin
                    if (byte_idx == 4'h0) begin
                        sending <= 1'b0;
                        buffer <= 1'b1;
                        cycles <= 16'h0;
                        scl_en <= 1'b1;
                        scl_val <= 1'b0;
                    end else begin
                        byte_idx <= byte_idx - 4'h1;
                    end
                end
            end else if (buffer) begin
                cycles <= cycles + 1;
                if (cycles < 16'd1000) begin
                    scl_en <= 1'b1;
                    sda_en <= 1'b1;
                    scl_val <= 1'b0;
                    sda_val <= 1'b0;
                end else if (cycles == 16'd1000) begin
                    scl_en <= 1'b0;
                    scl_val <= 1'b0;
                    buffer <= 1'b0;
                    stop_bit <= 1'b1;
                    cycles <= 16'h0;
                end
            end  else if (stop_bit) begin
                if (scl) begin
                    cycles <= cycles + 1;
                    if (cycles < `RISE) begin
                        sda_en <= 1'b1;
                        sda_val <= 1'b0;
                    end else if (cycles == `RISE) begin
                        sda_en <= 1'b0;
                        sda_val <= 1'b0;
                        stop_bit <= 1'b0;
                        cycles <= 16'h0;
                    end
                end
            end else begin
                if (start) begin
                    start_bit <= 1'b1;
                end
            end
        end
    end
endmodule : SendHello

module I2C (
    input logic clock, reset,
    input logic send_hello,
    output logic done, error,
    inout tri1 sda, scl
);

    logic start_sendclear, finished_sendclear;
    logic start_sendhello, finished_sendhello;

    SendClear sc(.clock, .reset, .start(start_sendclear),
                 .done(finished_sendclear), .sda, .scl, .error());
    SendHello sh(.clock, .reset, .start(start_sendhello),
                 .done(finished_sendhello), .sda, .scl, .error);

    logic [15:0] delay;

    logic sending_clear, buffer, sending_hello, is_done;
    assign start_sendclear = send_hello;
    assign start_sendhello = buffer & delay == 16'd2000;
    assign done = is_done;

    always_ff @(posedge clock, posedge reset) begin
        if (reset) begin
            sending_clear <= 1'b0;
            sending_hello <= 1'b0;
            is_done <= 1'b0;
            delay <= 16'h0;
            buffer <= 1'b0;
        end else begin
            if (sending_clear) begin
                // Send clear command first
                if (finished_sendclear) begin
                    sending_clear <= 1'b0;
                    buffer <= 1'b1;
                    delay <= 16'h0;
                end
            end else if (buffer) begin
                // Wait a little before sending HELLO as slave needs to get
                // ready
                delay <= delay + 1;
                if (delay == 16'd2000) begin
                    buffer <= 1'b0;
                    sending_hello <= 1'b1;
                end
            end else if (sending_hello) begin
                // Send ASCII codes for HELLO
                if (finished_sendhello) begin
                    sending_hello <= 1'b0;
                    is_done <= 1'b1;
                end
            end else if (is_done) begin
            end else begin
                if (send_hello) begin
                    sending_clear <= 1'b1;
                    delay <= 16'h0;
                end
            end
        end
    end
endmodule : I2C











