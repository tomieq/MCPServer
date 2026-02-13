FROM swift:6.1 as builder
WORKDIR /app
COPY . .
RUN swift build -c release
# aarch64-unknown-linux-gnu for raspberry pi
# x86_64-unknown-linux-gnu for intel based architectures
RUN mkdir output
RUN cp $(swift build --show-bin-path -c release)/MCPServer output/App
RUN strip -s output/App

FROM swift:6.1-slim
WORKDIR /app
COPY --from=builder /app/output/App .
CMD ["./App"]
