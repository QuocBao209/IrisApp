import cv2
import numpy as np
import sys
import os
from typing import Tuple

class IrisSegmentationError(Exception):
    pass


class IrisSegmenter:
    def __init__(self, output_size: int = 400):
        self.output_size = output_size

    def _preprocess(self, image_bgr: np.ndarray) -> np.ndarray:
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        clahe = cv2.createCLAHE(clipLimit=2.0, tileGridSize=(8, 8))
        gray = clahe.apply(gray)
        gray = cv2.equalizeHist(gray)
        gray = cv2.medianBlur(gray, 5)
        return gray

    def _detect_pupil(self, gray: np.ndarray) -> Tuple[int, int, int]:
        h, w = gray.shape
        margin = int(w * 0.12)
        roi = gray[margin:h-margin, margin:w-margin]

        blur = cv2.GaussianBlur(roi, (7, 7), 0)
        thr_val = max(1, int(np.percentile(blur, 8)))
        _, thresh = cv2.threshold(blur, thr_val, 255, cv2.THRESH_BINARY_INV)

        kernel = np.ones((5, 5), np.uint8)
        thresh = cv2.morphologyEx(thresh, cv2.MORPH_OPEN, kernel)
        thresh = cv2.morphologyEx(thresh, cv2.MORPH_CLOSE, kernel, iterations=2)

        contours, _ = cv2.findContours(thresh, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not contours:
            raise IrisSegmentationError("Không tìm thấy contour của đồng tử.")

        best_score = -1
        best_candidate = None

        for c in contours:
            area = cv2.contourArea(c)
            if area < 30:
                continue
            (cx, cy), r = cv2.minEnclosingCircle(c)
            circularity = area / (np.pi * r * r + 1e-6)

            if circularity >= 0.55 and circularity > best_score:
                best_score = circularity
                best_candidate = (cx + margin, cy + margin, r)

        if best_candidate is None:
            raise IrisSegmentationError("Không tìm thấy đồng tử hợp lệ.")

        return int(best_candidate[0]), int(best_candidate[1]), int(best_candidate[2])

    def _detect_iris_boundary(self, gray: np.ndarray, pupil_center: Tuple[int, int], pupil_radius: int) -> int:
        px, py = pupil_center
        h, w = gray.shape
        max_r = int(pupil_radius * 4.0)
        angles = np.linspace(0, 2 * np.pi, 360, endpoint=False)
        raw_radius = np.full(360, -1, dtype=np.float32)

        r_start = int(pupil_radius * 1.2)
        for i, theta in enumerate(angles):
            dx, dy = np.cos(theta), np.sin(theta)
            prev_val = None
            max_grad = 0
            best_r = -1

            for r_step in range(r_start, max_r):
                x = int(px + r_step * dx)
                y = int(py + r_step * dy)
                if not (0 <= x < w and 0 <= y < h):
                    break

                val = int(gray[y, x])
                if prev_val is not None and (val - prev_val) > max_grad:
                    max_grad = val - prev_val
                    best_r = r_step
                prev_val = val

            if best_r > 0:
                raw_radius[i] = best_r

        horiz_vals = [
            raw_radius[i] for i in range(360)
            if raw_radius[i] > 0 and (i < 50 or i > 310 or 130 < i < 230)
        ]

        nominal_r = float(np.median(horiz_vals)) if len(horiz_vals) > 6 else pupil_radius * 2.5
        return int(nominal_r)

    def _remove_eyelids_by_edge(self, gray: np.ndarray, base_mask: np.ndarray, pupil_center: Tuple[int, int], iris_r: int) -> np.ndarray:
        px, py = pupil_center
        h, w = gray.shape
        noise_mask = np.zeros_like(base_mask)

        y_top_start = max(0, py - iris_r)
        y_top_end = max(0, py - int(iris_r * 0.15))
        x_start = max(0, px - iris_r)
        x_end = min(w, px + iris_r)

        if y_top_end > y_top_start:
            top_roi = gray[y_top_start:y_top_end, x_start:x_end]
            blurred_top = cv2.GaussianBlur(top_roi, (7, 7), 0)
            edges_top = cv2.Canny(blurred_top, 20, 80)

            lines_top = cv2.HoughLinesP(edges_top, 1, np.pi/180, threshold=20,
                                        minLineLength=int(iris_r * 0.3), maxLineGap=int(iris_r * 0.1))

            if lines_top is not None:
                max_y_edge = 0
                found_valid_line = False
                for line in lines_top:
                    x1, y1, x2, y2 = line[0]
                    angle = np.abs(np.arctan2(y2 - y1, x2 - x1) * 180.0 / np.pi)
                    if angle < 30 or angle > 150:
                        max_y_edge = max(max_y_edge, y1, y2)
                        found_valid_line = True

                if found_valid_line and max_y_edge > 0:
                    global_eyelid_y = y_top_start + max_y_edge
                    noise_mask[0:global_eyelid_y, :] = 255

        y_bot_start = min(h, py + int(iris_r * 0.6))
        y_bot_end = min(h, py + iris_r)

        if y_bot_end > y_bot_start:
            bot_roi = gray[y_bot_start:y_bot_end, x_start:x_end]
            blurred_bot = cv2.GaussianBlur(bot_roi, (7, 7), 0)
            edges_bot = cv2.Canny(blurred_bot, 30, 100)

            lines_bot = cv2.HoughLinesP(edges_bot, 1, np.pi/180, threshold=20,
                                        minLineLength=int(iris_r * 0.3), maxLineGap=int(iris_r * 0.1))

            if lines_bot is not None:
                min_y_edge = bot_roi.shape[0]
                found_valid_line = False

                for line in lines_bot:
                    x1, y1, x2, y2 = line[0]
                    angle = np.abs(np.arctan2(y2 - y1, x2 - x1) * 180.0 / np.pi)
                    if angle < 30 or angle > 150:
                        min_y_edge = min(min_y_edge, y1, y2)
                        found_valid_line = True

                if found_valid_line:
                    global_eyelid_y_bot = y_bot_start + min_y_edge
                    noise_mask[global_eyelid_y_bot:h, :] = 255

        iris_spatial_area = np.zeros_like(base_mask)
        cv2.circle(iris_spatial_area, (px, py), iris_r, 255, -1)

        noise_inside_iris = cv2.bitwise_and(noise_mask, iris_spatial_area)
        cleaned_mask = cv2.bitwise_and(base_mask, cv2.bitwise_not(noise_inside_iris))

        return cleaned_mask

    def process(self, image_bgr: np.ndarray) -> np.ndarray:
        raw_gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        enhanced_gray = self._preprocess(image_bgr)

        px, py, pr = self._detect_pupil(enhanced_gray)
        iris_r = int(self._detect_iris_boundary(enhanced_gray, (px, py), pr) * 1.03)

        mask = np.zeros(raw_gray.shape, dtype=np.uint8)
        cv2.circle(mask, (px, py), iris_r, 255, -1)

        mask = self._remove_eyelids_by_edge(raw_gray, mask, (px, py), iris_r)

        x0 = max(0, px - iris_r)
        x1 = min(image_bgr.shape[1], px + iris_r)
        y0 = max(0, py - iris_r)
        y1 = min(image_bgr.shape[0], py + iris_r)

        crop_img = image_bgr[y0:y1, x0:x1].copy()
        crop_mask = mask[y0:y1, x0:x1]

        crop_img = cv2.resize(crop_img, (self.output_size, self.output_size), cv2.INTER_LINEAR)
        crop_mask = cv2.resize(crop_mask, (self.output_size, self.output_size), cv2.INTER_NEAREST)

        iris_final = cv2.bitwise_and(crop_img, crop_img, mask=crop_mask)
        return iris_final


if __name__ == "__main__":
    if len(sys.argv) < 3:
        print("ERROR: Usage: python iris_segment.py <input_path> <output_path>")
        sys.exit(1)

    input_path = sys.argv[1]
    output_path = sys.argv[2]

    if not os.path.exists(input_path):
        print(f"ERROR: Input file not found: {input_path}")
        sys.exit(1)

    img = cv2.imread(input_path)
    if img is None:
        print(f"ERROR: Cannot read image: {input_path}")
        sys.exit(1)

    try:
        segmenter = IrisSegmenter(output_size=400)
        result = segmenter.process(img)

        success = cv2.imwrite(output_path, result)
        if success:
            print(output_path)
        else:
            print("ERROR: Failed to save output image")
            sys.exit(1)

    except Exception as e:
        print(f"ERROR: {str(e)}")
        sys.exit(1)