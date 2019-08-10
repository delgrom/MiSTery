//
// mfp_timer.v
// 
// Single MFP68901 timer implementation
// http://code.google.com/p/mist-board/
// 
// Copyright (c) 2013 Stephen Leary
// Copyright (c) 2013-15 Till Harbaum <till@harbaum.org> 
// 
// This source file is free software: you can redistribute it and/or modify 
// it under the terms of the GNU General Public License as published 
// by the Free Software Foundation, either version 3 of the License, or 
// (at your option) any later version. 
// 
// This source file is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of 
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the 
// GNU General Public License for more details.
// 
// You should have received a copy of the GNU General Public License 
// along with this program.  If not, see <http://www.gnu.org/licenses/>. 


module mfp_timer(
	input        CLK,
	input        CLK_EN,
	input        RST, 
	input        DS,

	input        DAT_WE,
	input  [7:0] DAT_I,
	output [7:0] DAT_O,

	input        CTRL_WE,
	input  [4:0] CTRL_I,
	output [3:0] CTRL_O,

	input        XCLK_I,
	input        T_I, // ext. trigger in

	output       PULSE_MODE,  // pulse and event mode disables input port irq
	output       EVENT_MODE,

	output reg   T_O,
	output reg   T_O_PULSE,

	// current data bits are exported to allow mfp some rs232 bitrate
	// calculations
	output [7:0] SET_DATA_OUT
);

assign SET_DATA_OUT = data;

reg [7:0] data, down_counter, cur_counter;
reg [3:0] control;

assign PULSE_MODE = pulse_mode;
assign EVENT_MODE = event_mode;

wire[7:0] prescaler;         // prescaler value
reg [7:0] prescaler_counter; // prescaler counter

reg       count;

wire      started;

wire      delay_mode;
wire      event_mode;
wire      pulse_mode;

// async clock edge detect
reg xclk, xclk_r, xclk_r2;

// generate xclk_en from async clock input
always @(posedge XCLK_I) xclk <= ~xclk;

wire xclk_en = xclk_r2 ^ xclk_r;
always @(posedge CLK) begin
	xclk_r <= xclk;
	xclk_r2 <= xclk_r;
end

// from datasheet: 
// read value when the DS pin last gone high prior to the current read cycle
always @(posedge CLK) begin
	reg DS_last;
	DS_last <= DS;
	if (~DS_last & DS) cur_counter <= down_counter;
end

always @(posedge CLK) begin
	reg trigger_r, trigger_r2, trigger_r3, trigger_r4;
	reg timer_tick, timer_tick_r;

	if (RST === 1'b1) begin
		T_O     <= 1'b0;
		control <= 4'd0;
		data    <= 8'd0;
		down_counter <= 8'd0;
		count <= 1'b0;
		prescaler_counter <= 8'd0;
	end else begin

		// In the datasheet, it's mentioned that T_I must be no more than 1/4 of the Timer Clock frequency
		// In the "Atari ST internals", it's 1/4 of the MFP clock frequency
		// Use the later, it has less jitter to the CPU clock
		if (CLK_EN) begin
			trigger_r <= T_I;
			trigger_r2 <= trigger_r;
			trigger_r3 <= trigger_r2;
			trigger_r4 <= trigger_r3;
		end

		// if a write request comes from the main unit
		// then write the data to the appropriate register.
		if(DAT_WE) begin
			data <= DAT_I;
			// the counter itself is only loaded here if it's stopped
			if(!started)
				down_counter <= DAT_I;
		end

		if(CTRL_WE) begin
			control <= CTRL_I[3:0];
			if (CTRL_I[4] == 1'b1)
				T_O <= 1'b0;
		end 

		if (xclk_en) timer_tick_r <= timer_tick;

		count <= 1'b0;

		if (started) begin
			if (xclk_en) begin
				if(prescaler_counter >= prescaler) begin
					prescaler_counter <= 8'd0;
					timer_tick <= ~timer_tick;
				end else
					prescaler_counter <= prescaler_counter + 8'd1;
			end

			T_O_PULSE <= 1'b0;

			// handle event mode
			if (event_mode === 1'b1)
				if (CLK_EN && (~trigger_r4 & trigger_r3))
					count <= 1'b1;

			// handle delay mode
			if (delay_mode === 1'b1)
				if (xclk_en && (timer_tick ^ timer_tick_r))
					count <= 1'b1;

			// handle pulse mode
			if (pulse_mode === 1'b1)
				if (xclk_en && (timer_tick ^ timer_tick_r) && trigger_r)
					count <= 1'b1;

			if (count) begin

				// timeout pulse
				if (down_counter === 8'd1) begin

					// pulse the timer out
					T_O <= ~T_O;
					T_O_PULSE <= 1'b1;
					down_counter <= data;

				end else begin

					down_counter <= down_counter - 8'd1;
				end
			end
		end else begin
			prescaler_counter <= 8'd0;
		end
	end
end

assign prescaler = control[2:0] === 3'd1 ?  8'd03 :
                   control[2:0] === 3'd2 ?  8'd09 :
                   control[2:0] === 3'd3 ?  8'd15 :
                   control[2:0] === 3'd4 ?  8'd49 :
                   control[2:0] === 3'd5 ?  8'd63 :
                   control[2:0] === 3'd6 ?  8'd99 :
                   control[2:0] === 3'd7 ?  8'd199 : 8'd1;

assign delay_mode = control[3] === 1'b0;
assign pulse_mode = control[3] === 1'b1 & !event_mode;
assign event_mode = control[3:0] === 4'b1000;

assign started = control[3:0] != 4'd0;
assign DAT_O = cur_counter;
assign CTRL_O = control;

endmodule // mfp_timer
