
`timescale 1ns/10ps

module  CONV(
	input		clk,
	input		reset,
	output		reg busy,	
	input		ready,	
			
	output		reg [11:0]iaddr,
	input		[19:0]idata,	
	
	output	 	reg cwr,
	output	 	reg [11:0]caddr_wr,
	output	 	reg [19:0]cdata_wr,
	
	output	 	reg crd,
	output	 	reg [11:0]caddr_rd,
	input	 	[19:0]cdata_rd,
	
	output	 	reg [2:0]csel
	);

reg [2:0]state;
reg [2:0]n_state;
reg [3:0]count;
reg [3:0]count_temp;
reg [15:0]image;
reg [5:0]posx;
reg [5:0]posy;
wire [11:0]pos[0:8];
wire [11:0]cpos[0:3];
reg signed[19:0]zp_data[0:8];
reg signed[19:0]img_data[0:8];
reg signed[19:0]kernel0[0:8];
reg signed[19:0]kernel1[0:8];
reg signed[43:0]conv;
wire signed[43:0]cdata;
wire signed[19:0]cdata_round;
wire signed[43:0]cdata_bias;
reg signed[19:0]bias0;
reg signed[19:0]bias1;
reg kernel;
reg hold;
reg op_done;
reg signed[19:0]comp[0:1];

parameter IDLE  = 0;
parameter INPUT = 1;
parameter ZPAD  = 2;
parameter CONV  = 3;
parameter MAXP  = 4;
parameter FLAT  = 5;
parameter STOP  = 6;

integer i;

// FSM
always @(posedge clk or posedge reset) begin
	if (reset) begin
		state <= 0;		
	end
	else begin
		state <= n_state;
	end
end

always @(*) begin
	case(state)
		IDLE: n_state = INPUT;
		INPUT: n_state = (count == 9)? ZPAD : INPUT;
		ZPAD : n_state = CONV;
		CONV: begin
			if( &posx && &posy) n_state = (op_done)? MAXP : CONV;
			else n_state = (csel == 2)? IDLE : CONV;
		end
		MAXP: begin
			if(posx == 31 && posy == 31) n_state = (csel == 4)? FLAT : MAXP;
			else n_state = MAXP;
		end
		FLAT: begin
			if(posx == 31 && posy == 31) n_state = (count == 5)? STOP : FLAT;
			else n_state = FLAT;
		end
		default: n_state = state;
	endcase
end

always @(posedge clk or posedge reset) begin
	if (reset) begin
		busy <= 0;		
	end
	else begin
		case(state)
			INPUT: busy <= 1;
			STOP: busy <= 0;
			default: busy <= busy;
		endcase
	end
end

always @(posedge clk or posedge reset) begin
	if (reset) begin
		count <= 4'd0;		
	end
	else begin
		case(state)
			INPUT: count <= (count == 4'd9)? 4'd0 : count + 4'd1;
			CONV: count <= (count == 4'd2)? 4'd0 : count + 4'd1;
			MAXP: count <= (count == 4'd7)? 4'd0 : count + 4'd1;
			FLAT: count <= (count == 4'd5)? 4'd0 : count + 4'd1;
			default: count <= count;
		endcase
	end
end

always @(posedge clk or posedge reset) begin
	if (reset) begin
		count_temp <= 0;		
	end
	else begin
		count_temp <= count;
	end
end

// posx, posy for memory addr
always @(posedge clk or posedge reset) begin
	if (reset) begin
		posx <= 6'b111111;
		posy <= 6'b111111;		
	end
	else begin
		case(state)
			IDLE: begin
				if (posx == 63) begin
					posx <= 0;
					posy <= posy + 1;
				end
				else begin
					posx <= posx + 1;
					posy <= posy;
				end				
			end
			CONV: begin
				if(&posx && &posy) begin
					posx <= (op_done)? 0 : posx;
					posy <= (op_done)? 0 : posy;
				end
				else begin
					posx <= posx;
					posy <= posy;
				end
			end
			MAXP: begin
				if (posx == 31) begin
					posx <= (hold == 0)? 0 : posx;
					posy <= (hold == 0)? ( (posy == 31)? 0 : posy + 1) : posy;
				end
				else begin
					posx <= (hold == 0)? posx + 1 : posx;
					posy <= posy;
				end
			end
			FLAT: begin
				if (posx == 31) begin
					posx <= (hold == 0)? 0 : posx;
					posy <= (hold == 0)? posy + 1 : posy;
				end
				else begin
					posx <= (hold == 0)? posx + 1 : posx;
					posy <= posy;
				end
			end
			default: begin
				posx <= posx;
				posy <= posy;
			end
		endcase
	end
end

// control crd & cwr
always @(posedge clk or posedge reset) begin
	if (reset) begin
		hold <= 0;		
	end
	else begin
		case(state)
			CONV: hold <= 1;
			MAXP: begin
				hold <= (count == 6)? 0 : 1;
			end
			FLAT: hold <= (count == 4)? 0 : 1;
			default: hold <= hold;
		endcase
	end
end

// 9x9 memory addr calc
assign pos[0] = pos[4] - 65;
assign pos[1] = pos[4] - 64;
assign pos[2] = pos[4] - 63;
assign pos[3] = pos[4] - 1;
assign pos[4] = ( (posx == 0)? 1 : ( (posx == 63)? posx - 1 : posx) ) + ( ( (posy == 0)? 1 : ( (posy == 63)? posy - 1 : posy) ) << 6 );
assign pos[5] = pos[4] + 1;
assign pos[6] = pos[4] + 63;
assign pos[7] = pos[4] + 64;
assign pos[8] = pos[4] + 65;

always @(posedge clk or posedge reset) begin
	if (reset) begin
		iaddr <= 12'd0;		
	end
	else begin
		case(state)
			INPUT: begin
				iaddr <= (count == 9)? 0 : pos[count];
			end
			default: iaddr <= iaddr;
		endcase
	end
end

// data
always @(posedge clk or posedge reset) begin
	if (reset) begin
		for(i = 0; i < 9; i = i+1) begin
			img_data[i] <= 0; 		
		end
	end
	else begin
		case(state)
			INPUT: begin
				img_data[count_temp] <= ready? 0 : idata;
			end
			ZPAD: begin
				
				if (posx == 0) begin
					img_data[0] <= 0;
					img_data[1] <= zp_data[0];
					img_data[2] <= zp_data[1];
					img_data[3] <= 0;
					img_data[4] <= zp_data[3];
					img_data[5] <= zp_data[4];
					img_data[6] <= 0;
					img_data[7] <= zp_data[6];
					img_data[8] <= zp_data[7];
				end
				else if (posx == 63) begin
					img_data[0] <= zp_data[1];
					img_data[1] <= zp_data[2];
					img_data[2] <= 0;
					img_data[3] <= zp_data[4];
					img_data[4] <= zp_data[5];
					img_data[5] <= 0;
					img_data[6] <= zp_data[7];
					img_data[7] <= zp_data[8];
					img_data[8] <= 0;
				end
				else begin
					for(i = 0; i < 9; i = i+1) begin
						img_data[i] <= zp_data[i]; 		
					end
				end
			end
			MAXP: begin
				img_data[count_temp] <= (count_temp < 5)? cdata_rd : 0;
			end
			FLAT: begin
				img_data[0] <= cdata_rd;
			end
			default: begin
				for(i = 0; i < 9; i = i+1) begin
					img_data[i] <= img_data[i]; 		
				end
			end
		endcase
	end
end


// zero-padding for boundary
always @(*) begin
	case(state)
		ZPAD: begin
			if (posy == 0) begin
				zp_data[0] = 0;
				zp_data[1] = 0;
				zp_data[2] = 0;
				zp_data[3] = img_data[0];
				zp_data[4] = img_data[1];
				zp_data[5] = img_data[2];
				zp_data[6] = img_data[3];
				zp_data[7] = img_data[4];
				zp_data[8] = img_data[5];
			end
			else begin
				if (posy == 63) begin
					zp_data[0] = img_data[3];
					zp_data[1] = img_data[4];
					zp_data[2] = img_data[5];
					zp_data[3] = img_data[6];
					zp_data[4] = img_data[7];
					zp_data[5] = img_data[8];
					zp_data[6] = 0;
					zp_data[7] = 0;
					zp_data[8] = 0;
				end
				else begin
					for(i = 0; i < 9; i = i+1) begin
						zp_data[i] = img_data[i]; 		
					end
				end
			end
		end
		default: begin
			for(i = 0; i < 9; i = i+1) begin
				zp_data[i] = 0; 		
			end
		end
	endcase
end

// kernel 1
always @(posedge clk) begin
	kernel1[0] <= 20'hFDB55;
	kernel1[1] <= 20'h02992;
	kernel1[2] <= 20'hFC994;
	kernel1[3] <= 20'h050FD;
	kernel1[4] <= 20'h02F20;
	kernel1[5] <= 20'h0202D;
	kernel1[6] <= 20'h03BD7;
	kernel1[7] <= 20'hFD369;
	kernel1[8] <= 20'h05E68;
end

// kernel 0
always @(posedge clk) begin
	kernel0[0] <= 20'h0A89E;
	kernel0[1] <= 20'h092D5;
	kernel0[2] <= 20'h06D43;
	kernel0[3] <= 20'h01004;
	kernel0[4] <= 20'hF8F71;
	kernel0[5] <= 20'hF6E54;
	kernel0[6] <= 20'hFA6D7;
	kernel0[7] <= 20'hFC834;
	kernel0[8] <= 20'hFAC19;
end

// switch kernel to control csel
always @(posedge clk or posedge reset) begin
	if (reset) begin
		kernel <= 0;		
	end
	else begin
		case(state)
			INPUT: kernel <= 0;
			CONV: begin
				kernel <= (op_done)? 0 : ( (count == 2)? 1 : kernel );
			end
			MAXP: begin
				kernel <= (posx == 31 && posy == 31 && csel == 4)? 0 : ((op_done)? 1 : kernel);
			end
			FLAT: begin
				kernel <= (count == 2 || count == 5)? ~kernel : kernel;
			end
			default: kernel <= kernel;
		endcase
	end
end

// convolution
always @(posedge clk or posedge reset) begin
	if (reset) begin
		conv <= 0;
	end
	else begin
		case(state)
			CONV: begin
				case(kernel)
					0:conv <= (kernel0[0] * img_data[0]) + (kernel0[1] * img_data[1]) + (kernel0[2] * img_data[2]) + (kernel0[3] * img_data[3]) + (kernel0[4] * img_data[4]) + (kernel0[5] * img_data[5]) + (kernel0[6] * img_data[6]) + (kernel0[7] * img_data[7]) + (kernel0[8] * img_data[8]);
					1:conv <= (kernel1[0] * img_data[0]) + (kernel1[1] * img_data[1]) + (kernel1[2] * img_data[2]) + (kernel1[3] * img_data[3]) + (kernel1[4] * img_data[4]) + (kernel1[5] * img_data[5]) + (kernel1[6] * img_data[6]) + (kernel1[7] * img_data[7]) + (kernel1[8] * img_data[8]);
				endcase
			end
			default: conv <= conv;
		endcase
	end
end

always @(posedge clk or posedge reset) begin
 	if (reset) begin
 		caddr_wr <= 0; 		
 	end
 	else begin
 		case(state)
 			CONV: begin
 				caddr_wr <= posx + (posy << 6);
 			end
 			MAXP: begin
 				caddr_wr <= posx + (posy << 5);
 			end
 			FLAT: begin
 				caddr_wr <= (kernel == 0)? (posx << 1) + (posy << 6) : (posx << 1) + (posy << 6) + 1;
 			end
 			default: caddr_wr <= caddr_wr;
 		endcase
 	end
 end 

// bias0 for kernel 0, bias1 for kernel 1
always @(posedge clk) begin
	bias0 <= 20'h01310;
	bias1 <= 20'hF7295;
end

// round
assign cdata = (conv >>> 15) + 1;
assign cdata_bias = (cdata >>> 1) + ((kernel)? bias1 : bias0);
assign cdata_round = cdata_bias[19:0];


always @(posedge clk or posedge reset) begin
	if (reset) begin
		cdata_wr <= 0;		
	end
	else begin
		case(state)
			CONV: cdata_wr <= ( (cdata_round[19] == 1)? 0 : cdata_round ); // ReLU
			MAXP: cdata_wr <= (comp[0] < comp[1])? comp[1] : comp[0];
			FLAT: cdata_wr <= img_data[0];
			default: cdata_wr <= cdata_wr;
		endcase
	end
end

// operation done
always @(posedge clk or posedge reset) begin
	if (reset) begin
		op_done <= 0;		
	end
	else begin
		case(state)
			CONV: begin
				if (&posx && &posy) op_done <= (kernel == 1 && count == 1)? 1 : 0;
				else op_done <= 0;
			end
			MAXP: begin
				if (posx == 31 && posy == 31) op_done <= (count == 5)? 1 : 0;
				else op_done <= 0;
			end
			default: op_done <= op_done;
		endcase
	end
end

// csel
always @(posedge clk or posedge reset) begin
	if (reset) begin
		csel <= 0;		
	end
	else begin
		case(state)
			CONV: begin
				csel <= (op_done)? 3'b001 : ( (count == 1)? ( (kernel)? 3'b010 : 3'b001 ) : 0 );
			end
			MAXP: begin
				case(count)
					6: begin
						if (kernel == 0) csel <= 3'b011;
						else csel <= 3'b100;
					end
					7: begin
						if(posx == 31 && posy == 31) csel <= (count == 7)? 3 : ( (kernel == 0)? 3'b001 : 3'b010 );
						else csel <= (kernel == 0)? 3'b001 : 3'b010;
					end
					default: begin
						if (kernel == 0) csel <= 3'b001;
						else csel <= 3'b010;
					end
				endcase
			end
			FLAT: begin
				case(count)
					0: csel <= 3;
					1: csel <= 3;
					2: csel <= 5;
					3: csel <= 4;
					4: csel <= 4;
					5: csel <= 5;
				endcase
			end		 
			default: csel <= csel;
		endcase
	end
end

always @(posedge clk or posedge reset) begin
	if (reset) begin
		cwr <= 0;		
	end
	else begin
		case(state)
			CONV: begin
				cwr <= (count == 1)? 1 : 0;
			end
			MAXP: cwr <= (count == 6)? 1 : 0;
			FLAT: begin
				case(count)
					1: cwr <= 0;
					2: cwr <= 1;
					3: cwr <= 0;
					4: cwr <= 0;
					5: cwr <= 1;
					default: cwr <= 0;
				endcase
			end
			default: cwr <= cwr;
		endcase
	end
end

always @(posedge clk or posedge reset) begin
	if (reset) begin
		crd <= 0;		
	end
	else begin
		case(state)
			CONV: begin
				crd <= op_done? 1 : 0;
			end
			MAXP: crd <= (count == 7)? 1 : ( (count == 4)? 0 : crd );
			FLAT: begin
				case(count)
					0: crd <= 1;
					1: crd <= 1;
					2: crd <= 0;
					3: crd <= 1;
					4: crd <= 1;
					5: crd <= 0;
					default: crd <= 0;
				endcase
			end
			default: crd <= crd;
		endcase
	end
end


// addr calc for max-pooling
assign cpos[0] = (posx << 1) + (posy << 7);
assign cpos[1] = cpos[0] + 1;
assign cpos[2] = cpos[0] + 64;
assign cpos[3] = cpos[0] + 65;

always @(posedge clk or posedge reset) begin
	if (reset) begin
		caddr_rd <= 0;		
	end
	else begin
		case(state)
			MAXP: caddr_rd <= (count < 5)? cpos[count] : 0;
			FLAT: caddr_rd <= posx + (posy << 5);
			default: caddr_rd <= caddr_rd;
		endcase
	end
end

// compare for max-pooling
always @(posedge clk or posedge reset) begin
	if (reset) begin
		comp[0] <= 0;
		comp[1] <= 0;		
	end
	else begin
		case(state)
			MAXP: begin
				comp[0] <= (img_data[0] < img_data[1])? img_data[1] : img_data[0];
				comp[1] <= (img_data[2] < img_data[3])? img_data[3] : img_data[2];
			end
			default: begin
				comp[0] <= comp[0];
				comp[1] <= comp[1];
			end
		endcase
	end
end

endmodule