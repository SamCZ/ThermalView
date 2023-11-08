#import <AppKit/AppKit.h>
#include <iostream>
#include <vector>
#include <mutex>

#define GLFW_INCLUDE_NONE
#define GLFW_EXPOSE_NATIVE_COCOA
#include <GLFW/glfw3.h>
#include <GLFW/glfw3native.h>

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <glm/glm.hpp>

#include "ThermalDevice.hpp"

const char* ShaderString = R"(
#include <metal_stdlib>
using namespace metal;

struct Vertex
{
	float3 position [[attribute(0)]];
	float2 uv [[attribute(1)]];
};

struct v2f
{
    float4 position [[position]];
	float2 uv;
};

v2f vertex vertexMain(Vertex in [[stage_in]]) {
    v2f o;
    o.position = float4(in.position, 1.0);
	o.uv = in.uv;
    return o;
}

float4 fragment fragmentMain( v2f in [[stage_in]], texture2d< float > albedo [[texture(0)]])
{
	constexpr sampler linearSampler(mip_filter::linear,
                                    mag_filter::linear,
                                    min_filter::linear,
                                    s_address::repeat,
                                    t_address::repeat,
                                    max_anisotropy(16));

	float4 texel = albedo.sample(linearSampler, in.uv);

    return texel;
}
)";

typedef glm::vec3 float3;
typedef glm::vec2 float2;

struct Vertex
{
	float3 position;
	float2 uv;
};

std::mutex imageMutex;
std::vector<uint8*> imageData;

void HandleTermalVideoAsync(uvc_frame_t* frame)
{
	uint8* imgData = new uint8[frame->width * frame->height * 4];

	for (int i = 0; i < frame->data_bytes / 3; ++i)
	{
		uint8* target = imgData + (i * 4);
		uint8* source = (uint8*)frame->data + (i * 3);

		memcpy(target, source, 3);
		target[3] = 255;
	}

	imageMutex.lock();
	imageData.push_back(imgData);
	imageMutex.unlock();

	uvc_free_frame(frame);
}

int main()
{
	glfwInit();
	glfwWindowHint(GLFW_CLIENT_API, GLFW_NO_API);

	GLFWwindow* window = glfwCreateWindow(800, 600, "Test", nullptr, nullptr);

	const id<MTLDevice> gpu = MTLCreateSystemDefaultDevice();
	const id<MTLCommandQueue> queue = [gpu newCommandQueue];
	CAMetalLayer* swapchain = [CAMetalLayer layer];
	swapchain.device = gpu;
	swapchain.opaque = YES;

	NSWindow *nswindow = glfwGetCocoaWindow(window);
	nswindow.contentView.layer = swapchain;
	nswindow.contentView.wantsLayer = YES;

	glfwShowWindow(window);

	MTLClearColor color = MTLClearColorMake(0, 0, 0, 1);

	// Create vertex descriptor
	MTLVertexDescriptor* vertexDescriptor = [[MTLVertexDescriptor alloc] init];
	{
		MTLVertexBufferLayoutDescriptor* vertexBufferLayoutDescriptor = [[MTLVertexBufferLayoutDescriptor alloc] init];
		vertexBufferLayoutDescriptor.stride = sizeof(Vertex);
		vertexBufferLayoutDescriptor.stepRate = 1;
		vertexBufferLayoutDescriptor.stepFunction = MTLVertexStepFunctionPerVertex;
		vertexDescriptor.layouts[0] = vertexBufferLayoutDescriptor;

		{
			MTLVertexAttributeDescriptor* vertexAttributeDescriptor = [[MTLVertexAttributeDescriptor alloc] init];
			vertexAttributeDescriptor.bufferIndex = 0;
			vertexAttributeDescriptor.format = MTLVertexFormat::MTLVertexFormatFloat3;
			vertexAttributeDescriptor.offset = __offsetof(Vertex, position);
			vertexDescriptor.attributes[0] = vertexAttributeDescriptor;
		}

		{
			MTLVertexAttributeDescriptor* vertexAttributeDescriptor = [[MTLVertexAttributeDescriptor alloc] init];
			vertexAttributeDescriptor.bufferIndex = 0;
			vertexAttributeDescriptor.format = MTLVertexFormat::MTLVertexFormatFloat2;
			vertexAttributeDescriptor.offset = __offsetof(Vertex, uv);
			vertexDescriptor.attributes[1] = vertexAttributeDescriptor;
		}
	}

	// Load shaders
	NSError* errorLib = nullptr;
	id<MTLLibrary> library = [gpu newLibraryWithSource: [NSString stringWithUTF8String: ShaderString]
	                                                options: nullptr
	                                                  error: &errorLib];

	if (errorLib != nullptr)
	{
		std::cout << [errorLib.localizedDescription UTF8String] << std::endl;
		return 0;
	}

	id<MTLFunction> vertex = [library newFunctionWithName: [NSString stringWithUTF8String: "vertexMain"]];
	id<MTLFunction> fragment = [library newFunctionWithName: [NSString stringWithUTF8String: "fragmentMain"]];

	// Create pipeline state
	NSError* errorState = nullptr;
	MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
	descriptor.vertexFunction = vertex;
	descriptor.vertexDescriptor = vertexDescriptor;
	descriptor.fragmentFunction = fragment;
	descriptor.colorAttachments[0].pixelFormat = MTLPixelFormat::MTLPixelFormatBGRA8Unorm_sRGB;

	id<MTLRenderPipelineState> pipelineState = [gpu newRenderPipelineStateWithDescriptor: descriptor
	                                                                                    error: &errorState];
	[descriptor release];

	if (errorState != nullptr)
	{
		std::cout << [errorState.localizedDescription UTF8String] << std::endl;
		return 0;
	}
	// Create vertex buffer
	Vertex vertices[] = {
		{ { -0.5f,  -0.5f, 0.0f }, {0, 0} },
		{ { -0.5f, 0.5f, 0.0f }, {0, 1} },
		{ { 0.5f,  0.5f, 0.0f }, {1, 1} },


		{ {-0.5, -0.5, 0}, {0, 0} },
		{ {0.5, 0.5, 0}, {1, 1} },
		{ {0.5, -0.5, 0}, {1, 0} },
	};

	id<MTLBuffer> vertexBuffer = [gpu newBufferWithBytes: &vertices
	                                             length: sizeof(Vertex) * 6
	                                            options: MTLResourceStorageModeManaged];

	// Create texture
	id<MTLTexture> texture;
	{
		MTLTextureDescriptor* textureDescriptor = [[MTLTextureDescriptor alloc] init];
		textureDescriptor.mipmapLevelCount = 1;
		textureDescriptor.width = 256;
		textureDescriptor.height = 192;

		textureDescriptor.textureType = MTLTextureType2D;
		textureDescriptor.cpuCacheMode = MTLCPUCacheModeDefaultCache;

		MTLTextureUsage usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;

		textureDescriptor.usage = usage;
		textureDescriptor.resourceOptions = MTLResourceCPUCacheModeDefaultCache;
		textureDescriptor.pixelFormat = MTLPixelFormatRGBA8Unorm;
		texture = [gpu newTextureWithDescriptor: textureDescriptor];
		[textureDescriptor release];
	}

	uint8* imgData = new uint8[256 * 192 * 4];
	for (int i = 0; i < 256 * 192 * 4; ++i)
	{
		imgData[i] = rand() % 256;
	}
	imageData.push_back(imgData);

	// Init video
	TermalDeviceContext termalDeviceContext;
	InitTermalVideo(termalDeviceContext);

	while(glfwWindowShouldClose(window) == false)
	{
		glfwPollEvents();

		@autoreleasepool
		{
			//color.red = (color.red > 1.0) ? 0 : color.red + 0.01;

			id<CAMetalDrawable> surface = [swapchain nextDrawable];

			MTLRenderPassDescriptor *pass = [MTLRenderPassDescriptor renderPassDescriptor];
			pass.colorAttachments[0].clearColor = color;
			pass.colorAttachments[0].loadAction  = MTLLoadActionClear;
			pass.colorAttachments[0].storeAction = MTLStoreActionStore;
            pass.colorAttachments[0].texture = surface.texture;

			id<MTLCommandBuffer> buffer = [queue commandBuffer];
			id<MTLRenderCommandEncoder> encoder = [buffer renderCommandEncoderWithDescriptor:pass];

			//[encoder setFrontFacingWinding: MTLWinding::MTLWindingCounterClockwise];
			[encoder setRenderPipelineState: pipelineState];
            [encoder setCullMode:MTLCullMode::MTLCullModeNone];
			//[encoder setViewport: MTLViewport{0, 0, 800, 600, 0, 1}];

			[encoder setVertexBuffer:vertexBuffer
					 offset: 0
					atIndex: 0];

			[encoder setFragmentTexture: texture atIndex:0];

			[encoder drawPrimitives:MTLPrimitiveType::MTLPrimitiveTypeTriangle vertexStart:0 vertexCount: 6];

			[encoder endEncoding];
			[buffer presentDrawable:surface];
			[buffer commit];
		}

		{
			imageMutex.lock();
			if (!imageData.empty())
			{
				uint8* data = imageData[0];
				imageData.erase(imageData.begin());
				imageMutex.unlock();

				MTLRegion region = MTLRegionMake2D(0, 0, 256, 192);

				int bytesPerPixel = 4;
				[texture replaceRegion: region
				           mipmapLevel: (NSUInteger)0
				                 slice: (NSUInteger)0
				             withBytes: data
				           bytesPerRow: (NSUInteger)256 * bytesPerPixel
				         bytesPerImage: (NSUInteger)256 * 192 * bytesPerPixel];

				delete[] data;
			}
			else
			{
				imageMutex.unlock();
			}
		}
	}

	TermalStopVideo(termalDeviceContext);
	TermalDestroy(termalDeviceContext);

	glfwDestroyWindow(window);
	glfwTerminate();

	return 0;
}
