import os
import struct
import zlib

def read_ppm(file_path):
    with open(file_path, 'r') as f:
        header = f.readline().strip()
        if header not in ('P3', 'P6'):
            raise ValueError('Unsupported PPM format: ' + header)

        dimensions = f.readline().strip()
        while dimensions.startswith('#'):
            dimensions = f.readline().strip()
        width, height = map(int, dimensions.split())

        max_val = int(f.readline().strip())
        if max_val != 255:
            raise ValueError('Unsupported max value: ' + str(max_val))

        if header == 'P3':
            # ASCII format
            pixel_data = []
            for line in f:
                if line.startswith('#'):
                    continue
                pixel_data.extend(map(int, line.split()))
            pixel_data = bytes(pixel_data)
        else:
            # Binary format
            pixel_data = f.read()

        return width, height, pixel_data

def save_as_png(ppm_path, png_path):
    width, height, pixel_data = read_ppm(ppm_path)

    # Create a PNG file
    with open(png_path, 'wb') as png:
        # PNG file signature
        png.write(b'\x89PNG\r\n\x1a\n')

        # IHDR chunk
        ihdr_data = struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0)
        png.write(struct.pack('>I', len(ihdr_data)))
        png.write(b'IHDR')
        png.write(ihdr_data)
        png.write(struct.pack('>I', zlib.crc32(b'IHDR' + ihdr_data) & 0xffffffff))

        # IDAT chunk
        raw_data = b''.join(b'\x00' + pixel_data[i:i + width * 3] for i in range(0, len(pixel_data), width * 3))
        compressed_data = zlib.compress(raw_data, level=9)
        png.write(struct.pack('>I', len(compressed_data)))
        png.write(b'IDAT')
        png.write(compressed_data)
        png.write(struct.pack('>I', zlib.crc32(b'IDAT' + compressed_data) & 0xffffffff))

        # IEND chunk
        png.write(struct.pack('>I', 0))
        png.write(b'IEND')
        png.write(struct.pack('>I', zlib.crc32(b'IEND') & 0xffffffff))

def display_image(png_path):
    import os
    os.startfile(png_path)

if __name__ == '__main__':
    ppm_path = 'image.ppm'
    png_path = 'image.png'

    save_as_png(ppm_path, png_path)
    display_image(png_path)