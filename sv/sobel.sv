
module sober #(
    parameter SIZE = 1443,
    parameter DATA_WIDTH = 8
) (
    input  logic        clock,
    input  logic        reset,
    output logic        in_rd_en,
    input  logic        in_empty,
    input  logic [7:0] in_dout,
    output logic        out_wr_en,
    input  logic        out_full,
    output logic [7:0]  out_din
);

typedef enum logic [1:0] {IDLE, UPDATE, CACULATE, WRITE} state_types;
state_types state, state_c;

logic [7:0] sb, sb_c;

logic [18:0] counter;
logic [18:0] counter_c;

logic paddingControl;

logic [DATA_WIDTH-1:0] register__array[SIZE-1:0];
logic [DATA_WIDTH-1:0] register__array_c[SIZE-1:0];


logic signed [15:0] horizontal_gradient; 
logic signed [15:0] vertical_gradient;   
logic signed [15:0] horizontal_gradient_abs; 
logic signed [15:0] vertical_gradient_abs;  
logic [15:0] gradient_avg;
logic [7:0] edge_strength; 

// // shift
// always_ff @(posedge clock or posedge reset) begin
    
//     integer i;
//     integer j;
//     if (reset) begin
//         counter <= 0;
//         for (i = 0; i < SIZE; ++i) begin
//             register__array[i] <= 0;
//         end
//     end    
//     else  begin
//         if (!in_empty && shiftControl) begin
//             counter <= counter + 1;
//             for (j = SIZE-1; j > 0; j = j - 1) begin
//                 register__array[j] <= register__array[j-1];
//             end
//             register__array[0] <= in_dout;
//             // if (counter < 391325) begin
//             //     $display("%u", register__array[0]);
//             // end   
//         end

//     end
// end


always_ff @(posedge clock or posedge reset) begin
    if (reset == 1'b1) begin
        state <= IDLE;
        sb <= 8'h0;
        counter <= 0;
        
    end else begin
        state <= state_c;
        sb <= sb_c;
        register__array <= register__array_c;
        counter <= counter_c;
    end
end

always_comb begin
    in_rd_en  = 1'b0;
    out_wr_en = 1'b0;
    out_din   = 8'b0;
    state_c   = state;
    sb_c = sb;


    // 更新后的计算水平和垂直梯度代码，适应1443个元素的新结构
    horizontal_gradient = register__array[2] + (2 * register__array[1]) + register__array[0]
                        - register__array[1442] - (2 * register__array[1441]) - register__array[1440];
    vertical_gradient = register__array[1440] + (2 * register__array[720]) + register__array[0]
                    - register__array[1442] - (2 * register__array[722]) - register__array[2];


    // 获取梯度的绝对值
    horizontal_gradient_abs = horizontal_gradient[15] ? -horizontal_gradient : horizontal_gradient;
    vertical_gradient_abs = vertical_gradient[15] ? -vertical_gradient : vertical_gradient;

    // 计算梯度的绝对值平均，并限制结果在0到255之间，作为边缘强度

    gradient_avg = (horizontal_gradient_abs + vertical_gradient_abs) / 2;
    edge_strength = gradient_avg > 255 ? 8'hFF : gradient_avg[7:0];

    paddingControl = (counter - 1) < 720 || ( counter - 720 - 1 )  >= 388080 || (counter - 1)  % 720 == 1 || (counter - 1) % 720 == 0;

    case (state)


        IDLE: begin
            counter_c = 0;
            for (int i = 0; i < SIZE; ++i) begin
                register__array_c[i] = 0;
            end
            if (in_empty == 1'b1) begin
                state_c = IDLE;
                in_rd_en = 1'b0;
            end
            else begin
                state_c = UPDATE;
                in_rd_en = 1'b0;
            end
            sb_c = 0;
            out_wr_en = 0;
        end

        UPDATE:begin
            if (!in_empty) begin
                if (counter < 1442) begin
                    if (counter < 721) begin
                        state_c = WRITE;
                        sb_c = 0;
                    end
                    else if (counter >= 721) begin
                        state_c = UPDATE;
                    end                     
                end
                else begin
                    state_c = CACULATE;
                end
                    in_rd_en = 1'b1;
                    counter_c = counter + 1;
                    register__array_c[SIZE-1:1] = register__array[SIZE-2:0];
                    register__array_c[0] = in_dout;
            end
            else begin
                if (counter >= 388800) begin
                    state_c = WRITE;
                    sb_c = 0;
                end
                else begin
                    state_c = UPDATE;
                    in_rd_en = 1'b0;
                end
            end
            out_wr_en = 0;


        end

        CACULATE:begin
            in_rd_en = 1'b0;
            state_c = WRITE;
            if(paddingControl) begin
                sb_c = 0;
            end
            else begin
                sb_c = edge_strength;
            end
            out_wr_en = 0;
        end

        WRITE: begin
            if (out_full == 1'b0) begin  //modified
                out_din = sb;
                out_wr_en = 1'b1;
                state_c = counter >= 389521 ? IDLE : UPDATE; //modified
                in_rd_en = 1'b0;
            end
            //state_c = (counter >= 391324) ? DONE : WRITE; //modified

            
        end

        default: begin
            in_rd_en  = 1'b0;
            out_wr_en = 1'b0;
            out_din = 8'b0;
            state_c = IDLE;
            sb_c = 8'hX;
        end

    endcase
end

endmodule
