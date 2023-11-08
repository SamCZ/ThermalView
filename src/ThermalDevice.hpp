#pragma once

#include <libuvc/libuvc.h>
#include <stdio.h>
#include <unistd.h>

#include "Config.hpp"

void HandleTermalVideoAsync(uvc_frame_t* frame);

void cb(uvc_frame_t *frame, void *ptr)
{
	uvc_frame_t *rgb;
	uvc_error_t ret;
	enum uvc_frame_format *frame_format = (enum uvc_frame_format *)ptr;

	/* We'll convert the image from YUV/JPEG to BGR, so allocate space */
	rgb = uvc_allocate_frame(frame->width * frame->height * 3);
	if (!rgb)
	{
		printf("unable to allocate rgb frame!\n");
		return;
	}

	//printf("callback! frame_format = %d, width = %d, height = %d, length = %lu, ptr = %p\n",
	//	frame->frame_format, frame->width, frame->height, frame->data_bytes, ptr);

	switch (frame->frame_format)
	{
		case UVC_FRAME_FORMAT_H264:
			/* use `ffplay H264_FILE` to play */
			/* fp = fopen(H264_FILE, "a");
			 * fwrite(frame->data, 1, frame->data_bytes, fp);
			 * fclose(fp); */
			break;
		case UVC_COLOR_FORMAT_MJPEG:
			/* sprintf(filename, "%d%s", jpeg_count++, MJPEG_FILE);
			 * fp = fopen(filename, "w");
			 * fwrite(frame->data, 1, frame->data_bytes, fp);
			 * fclose(fp); */
			break;
		case UVC_COLOR_FORMAT_YUYV:
			/* Do the BGR conversion */
			//ret = uvc_any2bgr(frame, bgr);
			ret = uvc_any2rgb(frame, rgb);
			if (ret) {
				uvc_perror(ret, "uvc_any2bgr");
				uvc_free_frame(rgb);
				return;
			}
			break;
		case UVC_COLOR_FORMAT_UNCOMPRESSED:
			HandleTermalVideoAsync(frame);
			return;
		default:
			break;
	}

	if (frame->sequence % 30 == 0)
	{
		printf(" * got image %u\n",  frame->sequence);
	}

	HandleTermalVideoAsync(rgb);

	//uvc_free_frame(rgb);
}

struct TermalDeviceContext
{
	uvc_context_t* ctx = nullptr;
	uvc_device_t* dev = nullptr;
	uvc_device_handle_t* devh = nullptr;
	uvc_stream_ctrl_t ctrl;
};

void TermalStopVideo(TermalDeviceContext& context)
{
	uvc_stop_streaming(context.devh);
	puts("Done streaming.");
}
void TermalDestroy(TermalDeviceContext& context)
{
	/* Release our handle on the device */
	uvc_close(context.devh);
	puts("Device closed");

	/* Release the device descriptor */
	uvc_unref_device(context.dev);


	/* Close the UVC context. This closes and cleans up any existing device handles,
	 * and it closes the libusb context if one was not provided. */
	uvc_exit(context.ctx);
	puts("UVC exited");
}

uvc_error_t InitTermalVideo(TermalDeviceContext& context)
{
	uvc_error_t res;

	/* Initialize a UVC service context. Libuvc will set up its own libusb
	 * context. Replace NULL with a libusb_context pointer to run libuvc
	 * from an existing libusb context. */
	res = uvc_init(&context.ctx, NULL);

	if (res < 0) {
		uvc_perror(res, "uvc_init");
		return res;
	}

	puts("UVC initialized");

	/* Locates the first attached UVC device, stores in dev */
	res = uvc_find_device(
		context.ctx, &context.dev,
		UVC_VENDOR_ID, UVC_PRODUCT_ID, NULL); /* filter devices: vendor_id, product_id, "serial_num" */

	if (res < 0) {
		uvc_perror(res, "uvc_find_device"); /* no devices found */
	} else {
		puts("Device found");

		/* Try to open the device: requires exclusive access */
		res = uvc_open(context.dev, &context.devh);

		if (res < 0) {
			uvc_perror(res, "uvc_open"); /* unable to open device */
		} else {
			puts("Device opened");

			/* Print out a message containing all the information that libuvc
			 * knows about the device */
			uvc_print_diag(context.devh, stderr);

			const uvc_format_desc_t *format_desc = uvc_get_format_descs(context.devh);
			const uvc_frame_desc_t *frame_desc = format_desc->frame_descs;
			enum uvc_frame_format frame_format;
			int width = UVC_DEVICE_RES_WIDTH;
			int height = UVC_DEVICE_RES_HEIGHT;
			int fps = UVC_DEVICE_FPS;

			std::cout << "bDescriptorSubtype: " << format_desc->bDescriptorSubtype << std::endl;

			switch (format_desc->bDescriptorSubtype) {
				case UVC_VS_FORMAT_MJPEG:
					frame_format = UVC_COLOR_FORMAT_MJPEG;
					break;
				case UVC_VS_FORMAT_FRAME_BASED:
					frame_format = UVC_FRAME_FORMAT_H264;
					break;
				default:
					frame_format = UVC_FRAME_FORMAT_UNCOMPRESSED;
					break;
			}

			if (frame_desc && (!UVC_DEVICE_FORCE_DESC)) {
				width = frame_desc->wWidth;
				height = frame_desc->wHeight;
				fps = 10000000 / frame_desc->dwDefaultFrameInterval;
			}

			printf("\nFirst format: (%4s) %dx%d %dfps\n", format_desc->fourccFormat, width, height, fps);

			/* Try to negotiate first stream profile */
			res = uvc_get_stream_ctrl_format_size(
				context.devh, &context.ctrl, /* result stored in ctrl */
				frame_format,
				width, height, fps /* width, height, fps */
			);

			/* Print out the result */
			uvc_print_stream_ctrl(&context.ctrl, stderr);

			if (res < 0) {
				uvc_perror(res, "get_mode"); /* device doesn't provide a matching stream */
			} else {
				/* Start the video stream. The library will call user function cb:
				 *   cb(frame, (void *) 12345)
				 */
				res = uvc_start_streaming(context.devh, &context.ctrl, cb, (void *) 12345, 0);

				if (res < 0) {
					uvc_perror(res, "start_streaming"); /* unable to start stream */
				} else {
					puts("Streaming...");


				}
			}
		}
	}

	return res;
}