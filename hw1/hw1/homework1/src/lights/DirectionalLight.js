function MyOrtho(out, left, right, bottom, top, near, far) {
    let lr = 1 / (left - right);
    let bt = 1 / (bottom - top);
    let nf = 1 / (near - far);
    out[0] = -2 * lr;
    out[1] = 0;
    out[2] = 0;
    out[3] = 0;
    out[4] = 0;
    out[5] = -2 * bt;
    out[6] = 0;
    out[7] = 0;
    out[8] = 0;
    out[9] = 0;
    out[10] = 2 * nf;
    out[11] = 0;
    out[12] = (left + right) * lr;
    out[13] = (top + bottom) * bt;
    out[14] = (far + near) / (far - near);
    out[15] = 1;
    return out;
  }

class DirectionalLight {

    constructor(lightIntensity, lightColor, lightPos, focalPoint, lightUp, hasShadowMap, gl) {
        //this.mesh = Mesh.cube(setTransform(0, 0, 0, 0.2, 0.2, 0.2, 0));
        this.mesh = Mesh.cube(setTransform(0, 0, 0, 1, 1, 1, 0));
        
        this.mat = new EmissiveMaterial(lightIntensity, lightColor);
        this.lightPos = lightPos;
        this.focalPoint = focalPoint;
        this.lightUp = lightUp

        this.hasShadowMap = hasShadowMap;
        this.fbo = new FBO(gl);
        if (!this.fbo) {
            console.log("无法设置帧缓冲区对象");
            return;
        }
    }

    CalcLightMVP(translate, scale) {
        let lightMVP = mat4.create();
        let modelMatrix = mat4.create();
        let viewMatrix = mat4.create();
        let projectionMatrix = mat4.create();

        // Model transform

        mat4.identity(modelMatrix)
        mat4.translate(modelMatrix,modelMatrix, translate)
        mat4.scale(modelMatrix, modelMatrix, scale);
        // View transform
        mat4.lookAt(viewMatrix, this.lightPos, this.focalPoint, this.lightUp);

        // Projection transform
        // mat4.ortho的生成的投影矩阵是按照 z轴向屏幕里 来计算的，与此lab框架相反。因此在函数的参数里取 想要的zNear、zFar 的相反数
        //mat4.ortho(projectionMatrix,-100,100,-100,100,0,500)

        // 或
        // games101式M_ortho
        MyOrtho(projectionMatrix,-100,100,-80,80,0,-400);
        // 通过以下代码 将mvp变换后的坐标的z轴 取相反数，因为opengl gl比较深度值按照近小远大的原则。
        projectionMatrix[10]=-1*projectionMatrix[10];
        projectionMatrix[14]=-1*projectionMatrix[14];

        mat4.multiply(lightMVP, projectionMatrix, viewMatrix);
        mat4.multiply(lightMVP, lightMVP, modelMatrix);

        //console.log(lightMVP);
        return lightMVP;
    }
}
