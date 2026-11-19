# EKS 과정 샘플 앱 이미지. 저장소 최상위에서 빌드한다: docker build -f app/Dockerfile -t opslab-app:1.0.0 .
# 강사가 tools/mirror-images.sh build 로 빌드해 강사 ECR Public 에 올린다(과정 파일 images.app).
FROM public.ecr.aws/docker/library/python:3.12-slim
RUN pip install --no-cache-dir flask==3.0.3 gunicorn==22.0.0 psycopg2-binary==2.9.9 boto3==1.35.36 redis==5.0.8 \
 && useradd -u 10001 -m app && mkdir -p /opt/app/data && chown app /opt/app/data
WORKDIR /opt/app
COPY app/app.py .
USER 10001
EXPOSE 8080
# --preload: 시작 동작(_startup)을 마스터에서 한 번만 실행하고, 실패하면 컨테이너가 종료된다(CrashLoopBackOff 실습)
# --worker-tmp-dir /dev/shm: 읽기 전용 루트 파일시스템에서도 gunicorn 자체는 동작하게 한다
CMD ["gunicorn", "--preload", "-w", "1", "--threads", "8", "--timeout", "35", "--worker-tmp-dir", "/dev/shm", "-b", "0.0.0.0:8080", "--access-logfile", "-", "app:app"]
