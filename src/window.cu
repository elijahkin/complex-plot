#include "kernels.cu"
#include <GL/glut.h>

const float home_center_id = 0.0;
const float home_center_im = 0.0;
const float home_apothem_re = 1.0;

// Global variables
float center_re = home_center_id;
float center_im = home_center_im;
float apothem_re = home_apothem_re;

uint8_t *rgb;
Image render;
GLuint textureID;

int screenWidth, screenHeight;
int lastMouseX, lastMouseY;
bool mouseLeftDown = false;
bool displayInfo = false;

void mouse(int button, int state, int x, int y) {
  if (button == GLUT_LEFT_BUTTON) {
    if (state == GLUT_DOWN) {
      mouseLeftDown = true;
      lastMouseX = x;
      lastMouseY = y;
    } else if (state == GLUT_UP) {
      mouseLeftDown = false;
    }
  } else if (button == 3 || button == 4) { // Scroll up and down
    float scalar = (button == 3) ? 1.1 : 0.9;
    float step_size = 2 * apothem_re / (screenWidth - 1);
    center_re += (x - screenWidth / 2) * step_size * (1 - scalar);
    center_im -= (y - screenHeight / 2) * step_size * (1 - scalar);
    apothem_re *= scalar;
  }
  glutPostRedisplay();
}

void motion(int x, int y) {
  if (mouseLeftDown) {
    int deltaX = x - lastMouseX;
    int deltaY = y - lastMouseY;

    center_re -= 2 * deltaX * apothem_re / screenWidth;
    center_im += 2 * deltaY * apothem_re / screenWidth;

    // Update the last mouse position to the current position
    lastMouseX = x;
    lastMouseY = y;

    glutPostRedisplay();
  }
}

void keyboard(unsigned char key, int x, int y) {
  switch (key) {
  case 27: // Escape key
    cudaFree(rgb);
    exit(0);
    break;
  case 32: // Space
    center_re = home_center_id;
    center_im = home_center_im;
    apothem_re = home_apothem_re;
    break;
  case 96: // `
    displayInfo = !displayInfo;
    break;
  }
  glutPostRedisplay();
}

void drawString(float x, float y, float z, std::string &text) {
  // Save the current attributes (including color)
  glPushAttrib(GL_CURRENT_BIT);

  // Set text color to black
  glColor3f(0.0f, 0.0f, 0.0f);

  // Set initial raster position
  glRasterPos3f(x, y, z);

  for (char c : text) {
    if (c == '\n') {
      // Move to the next line
      y -= 0.05f;             // Adjust the line spacing as needed
      glRasterPos3f(x, y, z); // Set new raster position for the next line
    } else {
      // Render the character
      glutBitmapCharacter(GLUT_BITMAP_9_BY_15, c);
    }
  }
  glPopAttrib();
}

// Create info string to display if displayInfo is true
std::string getInfoString() {
  return "Center X: " + std::to_string(center_re) +
         "\nCenter Y: " + std::to_string(center_im) +
         "\nApothem: " + std::to_string(apothem_re);
}

void display() {
  // TODO move these calculations inside kernels
  float min_re = center_re - apothem_re;
  float max_re = center_re + apothem_re;
  float apothem_im = screenHeight * apothem_re / screenWidth;
  float max_im = center_im + apothem_im;
  float min_im = center_im - apothem_im;
  float step_size = 2 * apothem_re / (screenWidth - 1);

  // Use CUDA kernel to render function
  // TODO unify the three kernels
  domain_color_kernel<<<28, 128>>>(
      [] __device__(Complex z) { return exp(1 / z); }, render, min_re, max_im,
      step_size);

  // Image pattern = read_ppm("patterns/cannon.ppm");
  // conformal_map_kernel<<<28, 128>>>(
  //     [] __device__(Complex z) { return pow(z, -2); }, render, min_re,
  //     max_re, min_im, max_im, step_size, pattern);

  // escape_time_kernel<<<28, 128>>>(
  //     [] __device__(Complex z, Complex c) { return pow(z, 7) + c; }, render,
  //     min_re, max_im, step_size, 10);
  cudaDeviceSynchronize();

  // Update OpenGL texture with CUDA output
  glBindTexture(GL_TEXTURE_2D, textureID);
  glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0, render.width, render.height, GL_RGB,
                  GL_UNSIGNED_BYTE, render.rgb);

  // Clear the color buffer and set up for rendering
  glClear(GL_COLOR_BUFFER_BIT);
  glEnable(GL_TEXTURE_2D);

  // Draw textured rectangle
  glBegin(GL_QUADS);
  glTexCoord2f(0.0f, 0.0f);
  glVertex2f(-1.0f, 1.0f);
  glTexCoord2f(1.0f, 0.0f);
  glVertex2f(1.0f, 1.0f);
  glTexCoord2f(1.0f, 1.0f);
  glVertex2f(1.0f, -1.0f);
  glTexCoord2f(0.0f, 1.0f);
  glVertex2f(-1.0f, -1.0f);
  glEnd();

  // Disable texture mapping and swap buffers
  glDisable(GL_TEXTURE_2D);

  // Draw info string for debugging
  if (displayInfo) {
    std::string info = getInfoString();
    drawString(-0.98, 0.95, 0.0, info);
  }

  glutSwapBuffers();
}

int main(int argc, char **argv) {
  // Initialize GLUT
  glutInit(&argc, argv);

  // Set display mode
  glutInitDisplayMode(GLUT_DOUBLE | GLUT_RGB);

  // Get screen size
  screenWidth = glutGet(GLUT_SCREEN_WIDTH);
  screenHeight = glutGet(GLUT_SCREEN_HEIGHT);

  // Allocate CUDA memory
  cudaMallocManaged(&rgb, screenWidth * screenHeight * 3 * sizeof(uint8_t));
  render = {screenWidth, screenHeight, screenWidth * screenHeight, rgb};

  // Set up window size and name
  glutInitWindowSize(screenWidth, screenHeight);
  glutCreateWindow("Functiongram");

  // Set fullscreen
  glutFullScreen();

  // Set up OpenGL for texture mapping
  glEnable(GL_TEXTURE_2D);

  // Set texture parameters
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_NEAREST);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP);
  glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP);

  // Specify texture image data
  glTexImage2D(GL_TEXTURE_2D, 0, GL_RGB, screenWidth, screenHeight, 0, GL_RGB,
               GL_UNSIGNED_BYTE, rgb);

  // Set up the callback functions
  glutDisplayFunc(display);
  glutKeyboardFunc(keyboard);
  glutMouseFunc(mouse);
  glutMotionFunc(motion);

  // Enter the GLUT event processing loop
  glutMainLoop();

  return 0;
}
