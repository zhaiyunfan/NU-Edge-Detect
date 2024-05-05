# 基于FPGA的Canny边缘检测算法的流式RTL实现

## 项目介绍

该项目旨在Intel CYCLONE-IV-E EP4CE115 FPGA上实现Canny边缘检测的核心算法。具体来说，Canny边缘检测算法是一种经典的计算机视觉算法，广泛应用于图像处理和目标检测领域。通过实现该算法的流式RTL版本，我们可以在FPGA上实现高速、低功耗的边缘检测，为图像处理应用提供更高的性能和效果。

在这个项目中，我实现了灰度处理和sobel滤波两个核心算法，首先将BMP位图灰度处理成8bit灰度图，给出亮度信息，并使用sobel算法求图像中的梯度向量，以此来量化像素亮度变化的剧烈程度，作为边缘的判断依据。

## 整体架构

输入是8位深彩色BMP位图，分辨率为720*540，在验证仿真时在软件层面上拆除BMP头，以RGB三个通道各8bit，每个像素共24bit，逐像素输入到待测模块中；输出则是8bit的灰度像素，在软件层面上额外加上BMP头，形成灰度图像

由于边缘检测的图像处理没有两帧之间的数据依赖，所以可以直接使用流式架构，通过FIFO进行不同子模块间的数据流传输，以此以单个像素为单位进行流式传输，加速整体计算

一共分为两个模块，24bit RGB像素在通过同步FIFO输入到top模块中后，输出到灰度处理模块，灰度处理模块输入24bit RGB像素，将RGB三个通道的强度值求平均，输出8bit的灰度像素。灰度处理模块通过FIFO和sobel滤波模块连接。sobel滤波模块中实现了一个长度为720*2+3=1443的8bit移位寄存器，用于实现对任意像素及其周围8个像素3\*3的梯度求解功能，求出梯度并进行限位后，作为8bit灰度像素经FIFO缓冲后输出

考虑到线性的数据流，整个模块使用唯一同步时钟以方便开发

## 功能特性

### 灰度处理模块

灰度处理模块内部是一个两状态的状态机，分为计算灰度和写FIFO两个状态，灰度像素值和状态机状态在always_ff块中在时钟上升沿更新

计算状态下，灰度值的计算是通过简化的方法进行的。如果前一级的FIFO空，没有待处理数据，则保持在计算状态继续等待。如果前一级的fifo非空，将RGB值的红、绿、蓝三个分量相加，然后除以3。计算时将8位颜色值扩展两位变为10位以避免溢出，并使用$unsigned调用将其强制为无符号数处理，计算结果截断为8位。直接在一个周期中进行三个分量的求和，并除3，并转移至写FIFO状态。

在写FIFO状态下，如果后一级的FIFO已满，则保持写FIFO状态等待，如果后一级的fifo未满，给出FIFO写使能信号，输出灰度值并切换回计算状态等待下一个输入像素就绪。

### Sobel求解模块

sobel模块可以在实例化时依据不同的参数来适应不同尺寸的图片

其算法的主干部分是，通过一个3\*3的像素梯度求解矩阵，将其中心像素遍历整张图片中非边界的所有像素，以求得图片中每个像素处的梯度。为了适应流式架构，使用了一个长度为图片中两行再加上3个像素的移位寄存器，并将其进行按时钟沿的缓冲更新，这样只需要逐位进行移位，就可以保证遍历到图片中的每一个像素，并求出该像素所在位置的梯度，作为边缘亮度信息。

在计算中，对于图片上下左右的边界像素，当求解矩阵的中心处在边界像素上时，矩阵中而至少有3个像素落在图片有效像素之外，需要跳过计算，对计算结果进行填充输出。为了实现对图片边界像素的填充控制，使用了一个计数器（也可以使用伪坐标），维护当前矩阵中心像素的实际位置，如果其落在边界上，则根据实际情况控制跳过计算并输出0。

以720*540的图片为例，本模块使用了一个长度为1443的8bit移位寄存器，并使用一个计数器对当前移位寄存器尾部像素的绝对序号进行维护，每当尾部输入一个新像素，计数器加一。这两个寄存器在状态机状态转移中进行一拍的更新缓冲。待输出数据也进行了一拍的更新缓冲

```verilog
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

~~~~~~~~~~~~~~中间代码略~~~~~~~~~~~~

in_rd_en = 1'b1;
counter_c = counter + 1;
register__array_c[SIZE-1:1] = register__array[SIZE-2:0];
register__array_c[0] = in_dout;
```

该模块实现了一个四状态的状态机，分为空闲、更新、计算和写FIFO四个状态。

#### IDLE状态

在空闲状态下，先将移位寄存器内容和计数器内容，以及其对应的一拍缓冲归零。如果输入FIFO为空，则保持空闲状态等待输入，如果输入FIFO非空，则转移至更新状态，开始尝试更新移位寄存器，次过程中读写使能都控制为零。

#### UPDATE状态

在更新状态下，主要的任务是控制寄存器移位，并检查矩阵中心是否落在图片边界上，以控制计算和输出。

只要输入FIFO非空，就读使能有效，并更新计数器加一，并进行SIZE-1:1 = SIZE-2:0的移位，并将新数据写到队列尾部0地址处。

这里有一个难点，在于根据计算的需求，需要将1443个移位寄存器填满，才能开始进行计算（因为计算需要使用最左侧的3\*3数据所以需要前两行零3个），而根据边界像素填充的需求，需要在输出图片的第一行720个像素中填充0（此时移位寄存器只填充了不到720个），所以不能简单的通过将状态保持在更新状态而控制移位寄存器前1443个周期的初始化。

这里，使用计数器实现了一个控制逻辑，对于一个重置过的1443移位寄存器，需要先将其填满。

在更新状态中，假设输入FIFO非空，前1442个像素进入实际上是在进行初始化。对于输入的第一行数据，即计数器值1到720，利用这一片时钟输出第一行0，下一个状态转移至写FIFO，下一个待写入数据设置为0。对于剩余的待初始化像素，即计数器值721到1441，状态保持在更新。

当移位寄存器尾部是第1442个像素时，下一个进入的将是第1443个像素，届时可以进行计算，所以下一个状态将是计算。

额外的，如果输入FIFO空，需要判断是因为前一级阻塞还是因为本张图片处理完毕，同样通过计数器判断，如果计数器已经大于等于图片像素总数，则转移写FIFO状态准备重置，否则保持在更新状态等待前级输入。

#### CACULATE状态

计算相对比较简单，梯度计算实际上是用水平和垂直梯度计算矩阵和移位寄存器中的3\*3矩阵做乘法，进而得到两个方向上的梯度分量，然后根据符号位进行判断，获取绝对值，并求和做平均，这里可以用求和后算数右移实现，最终的边缘亮度强度就是该平均值在0到255上限位的结果

在这里我将这个计算逻辑和判断边界条件的填充控制bool信号paddingControl一起放在always_comb块中进行连续赋值，等待直接引用

```verilog
// 更新后的计算水平和垂直梯度代码，适应1443个元素的新结构
horizontal_gradient = register__array[2] + (register__array[1] + register__array[1]) + register__array[0]
                    - register__array[1442] - (register__array[1441] + register__array[1441]) - register__array[1440];
vertical_gradient = register__array[1440] + (register__array[720] + register__array[720]) + register__array[0]
                - register__array[1442] - (register__array[722] + register__array[722]) - register__array[2];


// 获取梯度的绝对值
horizontal_gradient_abs = horizontal_gradient[15] ? -horizontal_gradient : horizontal_gradient;
vertical_gradient_abs = vertical_gradient[15] ? -vertical_gradient : vertical_gradient;

// 计算梯度的绝对值平均，并限制结果在0到255之间，作为边缘强度

gradient_avg = (horizontal_gradient_abs + vertical_gradient_abs) / 2;
//gradient_avg = (horizontal_gradient_abs + vertical_gradient_abs) >>> 1;
edge_strength = gradient_avg > 255 ? 8'hFF : gradient_avg[7:0];

paddingControl = (counter - 1) < 720 || ( counter - 720 - 1 )  >= 388080 || (counter - 1)  % 720 == 1 || (counter - 1) % 720 == 0;
```

这部分的难点依然是图片边界的控制，在更新状态中已经处理了初始化时第一行的0填充的控制，在计算状态中进行第一列和最后一列，以及最后一行的0填充控制。

需要明确的是，conter指向队列中最后一个，也就是最新一个元素，矩阵中心元素在其左上方，所以如果要判断中心元素是否落在边界上，只需判断conter指向元素的左侧元素是否落在边界上，因为其与中心元素同列，即```(counter - 1)  % 720 == 1 || (counter - 1) % 720 == 0```

如果要判断中心元素是否落在第一行或最后一行，只需要```(counter - 1) < 720 || ( counter - 720 - 1 )  >= 总像素数```

如果满足以上填充判断条件，待输出数据即设置为0，否则正常输出，将待输出数据设置为边缘强度值

下一个状态设置为写FIFO

#### WRITE状态

在写FIFO状态中，如果输出FIFO非空，则可以输出，否则保持在WRITE状态等待输出

在写FIFO时，设置待写数据和写使能，并根据计数器状态判断是否排空移位寄存器，进而判断是结束当前图片返回空闲状态重置等待下一张图片，还是转移至更新状态继续进行移位

当图片中最后一个像素输入到移位寄存器中后，计数器值为图片像素总数，此时由于矩阵中心不在寄存器尾部，所以仍有最后一行零一个像素没有输出（虽然都是边界像素需要填充0），判断couter是否大于像素总数+图片宽度，如果大于则下一个状态转移到空闲状态结束该图片，否则转移到更新状态继续处理。

## 性能表现

使用Synopsys的Synplify工具进行综合，可以得到估计最大时钟频率39Mhz，由于在仿真时，时钟周期是10，timescale使用了时间单位1ns时间精度1ns，即仿真时时钟频率是100Mhz，此时需要11,664,275ns完成一整张720*540图片的处理，即0.01秒一张图片，100FPS，考虑到实际综合后最大时钟频率只有39Mhz，可以估计其实际帧速率可以达到30FPS以上

## 验证测试

起初使用的是SV实现了testbench，进行逐位验证，后来将该testbench重构为UVM架构，使用UVM进行验证

## Project Introduction

This project aims to implement the core algorithm of Canny edge detection on the Intel CYCLONE-IV-E EP4CE115 FPGA. Specifically, the Canny edge detection algorithm is a classical computer vision algorithm widely used in image processing and object detection fields. By implementing a streaming RTL version of this algorithm, we can achieve high-speed and low-power edge detection on FPGA, offering enhanced performance and effects for image processing applications.

In this project, I implemented the grayscale processing and Sobel filtering, two core algorithms. First, the BMP bitmap is processed into an 8-bit grayscale image to give brightness information, and the Sobel algorithm is used to calculate the gradient vector in the image to quantify the severity of pixel brightness changes, serving as the basis for edge detection.

## Overall Architecture

The input is an 8-bit depth color BMP bitmap with a resolution of 720*540. In verification simulation, the BMP header is removed at the software level, with RGB channels each of 8 bits, totaling 24 bits per pixel, which are input to the module being tested pixel by pixel; the output is an 8-bit grayscale pixel, with the BMP header added at the software level to form a grayscale image.

Since there is no data dependency between two frames in edge detection image processing, a streaming architecture can be used directly, accelerating the overall computation by transferring data between different sub-modules through FIFO, transmitting on a per-pixel basis.

There are two modules in total. After the 24-bit RGB pixels are input to the top module via synchronous FIFO, they are output to the grayscale processing module. The grayscale processing module inputs 24-bit RGB pixels, averages the intensity values of the RGB channels, and outputs 8-bit grayscale pixels. The grayscale module is connected to the Sobel filter module via FIFO. The Sobel filter module implements a shift register of 720*2+3=1443 8-bit lengths, to calculate the 3*3 gradient around any pixel, and the computed gradient, after being limited, is output through FIFO buffering as an 8-bit grayscale pixel.

Considering the linear data flow, the entire module uses a single synchronous clock for ease of development.

## Functional Features

### Grayscale Processing Module

Inside the grayscale processing module is a two-state state machine, divided into calculating grayscale and writing FIFO. The grayscale pixel value and state machine state are updated on the clock's rising edge in the always_ff block.

In the calculate state, the calculation of the grayscale value is done using a simplified method. If the previous FIFO is empty with no data to process, it remains in the calculate state waiting. If the previous FIFO is not empty, the RGB values of red, green, and blue components are added together and then divided by 3. The calculation expands the 8-bit color value by two bits to 10 bits to avoid overflow, treating it as an unsigned number with $unsigned, and the result is truncated to 8 bits. All three components are added and divided by 3 in one cycle, moving to the write FIFO state.

In the write FIFO state, if the next FIFO is full, it remains in the write FIFO state waiting. If the next FIFO is not full, the FIFO write enable signal is given out, the grayscale value is output, and it switches back to the calculate state waiting for the next input pixel to be ready.

### Sobel Solver Module

The Sobel module can be instantiated with different parameters to accommodate different image sizes.

The core part of the algorithm uses a 3*3 pixel gradient solver matrix, iterating over all the non-border pixels in the entire image to obtain the gradient at each pixel. To adapt to the streaming architecture, a shift register the length of two rows plus three pixels of the image is used, and it is updated on the clock edge buffering, so just by shifting bit by bit, every pixel in the image can be traversed, and the gradient at that position can be obtained as edge brightness information.

In the calculations, for the border pixels on the top, bottom, left, and right of the image, when the center of the solver matrix is on a border pixel, at least three pixels in the matrix fall outside the valid pixels of the image, and the calculation needs to be skipped, with the result filled out. To implement control over padding the image border pixels, a counter (or pseudo coordinates) is used to maintain the actual position of the center pixel in the matrix. If it falls on the border, the calculation is skipped according to the actual situation, and 0 is output.

Taking an image of 720*540 as an example, this module uses a shift register of 1443 8-bit lengths and uses a counter to maintain the absolute sequence number of the tail pixel in the shift register. Whenever a new pixel enters the tail, the counter increments. These two registers are updated in a state machine state transition buffer. The data to be output is also updated in a buffer.

This module implements a four-state state machine, divided into Idle, Update, Calculate, and Write FIFO four states.

#### IDLE State

In the idle state, first, the content of the shift register and the counter, along with their corresponding buffers, are reset to zero. If the input FIFO is empty, it remains in the idle state waiting for input. If the input FIFO is not empty, it moves to the update state, beginning to try to update the shift register, with read/write enable controlled to zero during this process.

#### UPDATE State

In the update state, the main task is to control the shift of the register and check whether the matrix center falls on the image border to control the calculation and output.

As long as the input FIFO is not empty, the read enable is valid, and the counter is incremented by one, performing the shift from SIZE-1:1 = SIZE-2:0 and writing the new data to the queue tail at address 0.

There is a challenge here, which is that according to the calculation requirements, it is necessary to fill the 1443 shift registers before starting the calculation (because the calculation needs to use the leftmost 3*3 data, so the first two rows of zeros are needed), and according to the requirement to fill the border pixels, it is necessary to fill the first row of 720 pixels with zeros (at this time, the shift register is filled with less than 720 pixels), so it cannot be simply controlled by maintaining the update state to initialize the first 1443 cycles of the shift register.

Here, a control logic is implemented using a counter. For a reset 1443 shift register, it needs to be filled first.

In the update state, assuming the input FIFO is not empty, the first 1442 pixels entering are actually being initialized. For the data of the first row, that is, counter values 1 to 720, use this period to output the first row of 0, the next state transition to write FIFO, the next data to be written is set to 0. For the remaining pixels to be initialized, that is, counter values 721 to 1441, the state remains updated.

When the tail of the shift register is the 1442nd pixel, the next one to enter will be the 1443rd pixel, and at that time, it can proceed to calculation, so the next state will be calculation.

Additionally, if the input FIFO is empty, it needs to be determined whether it is due to a blockage in the previous stage or because the processing of this image is complete, also judged by the counter. If the counter has already exceeded the total number of image pixels, then transition to write FIFO state to prepare for resetting; otherwise, remain in the update state waiting for input from the previous stage.

#### CALCULATE State

The calculation is relatively simple. The gradient calculation is actually done by multiplying the horizontal and vertical gradient calculation matrices with the 3*3 matrix in the shift register, thus obtaining two directional gradient components, then judging by the sign bit, obtaining the absolute value, and averaging by summing and arithmetic right shifting, the final edge brightness intensity is the result of this average value limited to 0 to 255.

Here, I put this calculation logic and the control signal paddingControl for judging border conditions together in the always_comb block for continuous assignment, waiting for direct reference.

The difficulty here is still the control of the image border. The control of the first row of 0 padding during initialization has been processed in the update state. In the calculation state, the control of the first and last columns, as well as the last row of 0 padding, is performed.

It should be clarified that the conter points to the last, i.e., the newest element in the queue, and the matrix center element is to its upper left, so to judge whether the center element falls on the border, just judge whether the element to the left of the conter element falls on the border, because it is in the same column as the center element, that is, ```(counter - 1) % 720 == 1 || (counter - 1) % 720 == 0```

To judge whether the center element falls on the first or last row, just ```(counter - 1) < 720 || ( counter - 720 - 1 ) >= total pixel count```

If the above padding judgment conditions are met, the data to be output is set to 0, otherwise, it is normally output, setting the data to be output to the edge intensity value.

The next state is set to write FIFO.

#### WRITE State

In the WRITE state of a FIFO, if the output FIFO is not empty, output can occur; otherwise, the system remains in the WRITE state waiting to output.

When writing to the FIFO, set the data to be written and the write enable, and determine whether to empty the shift register based on the counter state. This decision leads to either ending the current image and returning to the idle state to wait for the next image, or moving to the update state to continue shifting.

After the last pixel of the image is input into the shift register, and the counter value equals the total number of pixels in the image, the center of the matrix is not at the tail of the register. Therefore, there is still one last row of zeros that has not been outputted (though these are boundary pixels which need to be filled with 0). Check if the counter is greater than the total number of pixels plus the image width. If it is, then the next state transitions to the idle state to end the processing of this image; otherwise, it transitions to the update state to continue processing.

## Performance

Using Synopsys' Synplify tool for synthesis, an estimated maximum clock frequency of 39 MHz is obtained. During simulation, the clock cycle was set to 10, with a timescale using 1ns time units and 1ns time precision, equivalent to a simulation clock frequency of 100 MHz. It takes 11,664,275ns to process a complete 720*540 image, approximately 0.01 seconds per image, achieving 100 FPS. Considering that the actual synthesized maximum clock frequency is only 39 MHz, the actual frame rate can be estimated to exceed 30 FPS.

## Verification and Testing

Initially, a testbench implemented in SystemVerilog was used for bit-by-bit verification. Later, this testbench was refactored into a UVM architecture, using UVM for verification.
