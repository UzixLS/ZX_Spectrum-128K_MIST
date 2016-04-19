//
// scandoubler.v
// 
// Copyright (c) 2015 Till Harbaum <till@harbaum.org> 
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

// TODO: Delay vsync one line

module scandoubler
(
	// system interface
	input            clk_x2,

	// scanlines (00-none 01-25% 10-50% 11-75%)
	input      [1:0] scanlines,

	// shifter video interface
	input            hs_in,
	input            vs_in,
	input      [5:0] r_in,
	input      [5:0] g_in,
	input      [5:0] b_in,

	// output interface
	output reg       hs_out,
	output reg       vs_out,
	output reg [5:0] r_out,
	output reg [5:0] g_out,
	output reg [5:0] b_out
);

reg clk;
always @(posedge clk_x2) clk <= ~clk;

// --------------------- create output signals -----------------
// latch everything once more to make it glitch free and apply scanline effect
reg scanline;
always @(posedge clk_x2) begin
   hs_out <= hs_sd;
   vs_out <= vs_in;

   // reset scanlines at every new screen
   if(vs_out != vs_in) scanline <= 0;

   // toggle scanlines at begin of every hsync
   if(hs_out && !hs_sd) scanline <= !scanline;

   // if no scanlines or not a scanline
   if(!scanline || !scanlines) begin
      r_out <= sd_out[17:12];
      g_out <= sd_out[11:6];
      b_out <= sd_out[5:0];
   end else begin
      case(scanlines)
			1: begin // reduce 25% = 1/2 + 1/4
				r_out <= {1'b0, sd_out[17:13]} + {2'b00, sd_out[17:14]};
				g_out <= {1'b0, sd_out[11:7] } + {2'b00, sd_out[11:8] };
				b_out <= {1'b0, sd_out[5:1]  } + {2'b00, sd_out[5:2]  };
			end

			2: begin // reduce 50% = 1/2
				r_out <= {1'b0, sd_out[17:13]};
				g_out <= {1'b0, sd_out[11:7]};
				b_out <= {1'b0, sd_out[5:1]};
			end

			3: begin // reduce 75% = 1/4
				r_out <= {2'b00, sd_out[17:14]};
				g_out <= {2'b00, sd_out[11:8]};
				b_out <= {2'b00, sd_out[5:2]};
			end
      endcase
   end
end

// scan doubler output register
reg [17:0] sd_out;

// ==================================================================
// ======================== the line buffers ========================
// ==================================================================

// 2 lines of 1024 pixels 3*4 bit RGB
(* ramstyle = "no_rw_check" *) reg [17:0] sd_buffer[2047:0];

// use alternating sd_buffers when storing/reading data   
reg        line_toggle;

// total hsync time (in 16MHz cycles), hs_total reaches 1024
reg  [9:0] hs_max;
reg  [9:0] hs_rise;
reg  [9:0] hcnt;

always @(negedge clk) begin
	reg hsD, vsD;

	hsD <= hs_in;

	// falling edge of hsync indicates start of line
	if(hsD && !hs_in) begin
		hs_max <= hcnt;
		hcnt <= 0;
	end else begin
		hcnt <= hcnt + 1'd1;
	end

	// save position of rising edge
	if(!hsD && hs_in) hs_rise <= hcnt;

   vsD <= vs_in;
   if(vsD != vs_in) line_toggle <= 0;

   // begin of incoming hsync
   if(hsD && !hs_in) line_toggle <= !line_toggle;

	sd_buffer[{line_toggle, hcnt}] <= {r_in, g_in, b_in};
end

// ==================================================================
// ==================== output timing generation ====================
// ==================================================================

reg  [9:0] sd_hcnt;
reg        hs_sd;

// timing generation runs 32 MHz (twice the input signal analysis speed)
always @(posedge clk_x2) begin
	reg hsD;

	hsD <= hs_in;

	// output counter synchronous to input and at twice the rate
	sd_hcnt <= sd_hcnt + 1'd1;
	if(hsD && !hs_in)     sd_hcnt <= hs_max;
	if(sd_hcnt == hs_max) sd_hcnt <= 0;

	// replicate horizontal sync at twice the speed
	if(sd_hcnt == hs_max)  hs_sd <= 0;
	if(sd_hcnt == hs_rise) hs_sd <= 1;

	// read data from line sd_buffer
	sd_out <= sd_buffer[{~line_toggle, sd_hcnt}];
end

endmodule
