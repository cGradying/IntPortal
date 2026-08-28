struct Frame1: View {
  var body: some View {
    ZStack() {
      ZStack() {
        Rectangle()
          .foregroundColor(.clear)
          .frame(width: 1680, height: 1050)
          .background(.white)
          .offset(x: 420, y: 0) 
        Rectangle()
          .foregroundColor(.clear)
          .frame(width: 840, height: 1051)
          .background(Color(red: 0.06, green: 0, blue: 0.01))
          .offset(x: 0, y: 0.50)
        Rectangle()
          .foregroundColor(.clear)
          .frame(width: 271, height: 28)
          .offset(x: -204.50, y: -447)
        Text("Welcome.\nStart your study session now with \nInt Portal!")
          .font(Font.custom("Poppins", size: 56).weight(.light))
          .lineSpacing(67.20)
          .italic()
          .foregroundColor(Color(red: 1, green: 0, blue: 0.02))
          .offset(x: -56, y: 127)
        ZStack() {
          Ellipse()
            .foregroundColor(.clear)
            .frame(width: 379, height: 379)
            .background(Color(red: 1, green: 0.22, blue: 0.24))
            .offset(x: 344.50, y: 412.50)
            .blur(radius: 550))
        }
        .frame(width: 840, height: 1050)
        .offset(x: 0, y: 0)
        Text("PUPSIS IntPortal")
          .font(Font.custom("Poppins", size: 28).weight(.bold))
          .tracking(2.80)
          .lineSpacing(28)
          .italic()
          .foregroundColor(.white)
          .offset(x: -204.50, y: -447)
      }
      .frame(width: 840, height: 1050)
      .offset(x: -419.50, y: 0)
      VStack(spacing: 32) {
        VStack(alignment: .leading, spacing: 16) {
          Text("Login to your PUP SIS account")
            .font(Font.custom("Poppins", size: 28).weight(.semibold))
            .lineSpacing(28)
            .foregroundColor(Color(red: 0.06, green: 0.09, blue: 0.16))
        }
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
              Text("Student Number")
                .font(Font.custom("Poppins", size: 16))
                .lineSpacing(16)
                .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.33))
            }
            HStack(alignment: .top, spacing: 8) {
              HStack(spacing: 5) {
                Text("Student Number (eg. 2000-00000-MN-00)")
                  .font(Font.custom("Poppins", size: 14))
                  .lineSpacing(14)
                  .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.33))
                  .opacity(0.50)
                HStack(spacing: 8) {

                }
                .foregroundColor(.clear)
              }
              .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color(red: 0.82, green: 0.91, blue: 1), lineWidth: 1.50)
              )
            }
            .frame(height: 48)
          }
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
              Text("Date of birth")
                .font(Font.custom("Poppins", size: 16))
                .lineSpacing(16)
                .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.33))
            }
            HStack(alignment: .top, spacing: 8) {
              HStack(spacing: 5) {
                Text(" Month")
                  .font(Font.custom("Poppins", size: 14))
                  .lineSpacing(14)
                  .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.33))
                  .opacity(0.50)
                VStack(alignment: .leading, spacing: 10) {
                  ZStack() {

                  }
                  .frame(width: 24, height: 24)
                  .offset(x: 0.50, y: -0.50)
                }
                .padding(10)
                .frame(width: 27, height: 25)
                .offset(x: 35, y: 0.50)
              }
              .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))    
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color(red: 0.82, green: 0.91, blue: 1), lineWidth: 1.50)
              )
            }
            .frame(width: 109, height: 38)
            HStack(alignment: .top, spacing: 8) {
              HStack(spacing: 5) {
                Text("Day")
                  .font(Font.custom("Poppins", size: 14))
                  .lineSpacing(14)
                  .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.33))
                  .opacity(0.50)
                ZStack() {
                  ZStack() {

                  }
                  .frame(width: 24, height: 24)
                  .offset(x: 0, y: 0)
                }
                .frame(width: 24, height: 24)
                .offset(x: 38.50, y: 0)
              }
              .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color(red: 0.82, green: 0.91, blue: 1), lineWidth: 1.50)
              )
            }
            .frame(width: 109, height: 38)
            .offset(x: -0.50, y: 14)
            VStack(alignment: .leading, spacing: 10) {
              ZStack() {
                Text("Year")
                  .font(Font.custom("Poppins", size: 14))
                  .lineSpacing(14)
                  .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.33))
                  .offset(x: -14.50, y: 0)
                HStack(spacing: 8) {
                  ZStack() {

                  }
                  .frame(width: 24, height: 24)
                  .offset(x: 0, y: 0)
                }
                .offset(x: 38.50, y: 0)
              }
              .frame(width: 109, height: 38)
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .stroke(Color(red: 0.82, green: 0.91, blue: 1), lineWidth: 1.50)
              )
            }
            .frame(width: 109)
            .offset(x: 143.50, y: 14)
          }
          VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: undefined) {
              Text("Password")
                .font(Font.custom("Poppins", size: 16))
                .lineSpacing(16)
                .foregroundColor(Color(red: 0.20, green: 0.25, blue: 0.33))
              Text()
            }
            VStack(alignment: .leading, spacing: 8) {
              HStack(spacing: 5) {
                Text("Enter your password")
                  .font(Font.custom("Poppins", size: 14))
                  .lineSpacing(14)
                  .foregroundColor(Color(red: 0.60, green: 0.64, blue: 0.70))
                HStack(spacing: 8) {
                  ZStack() {

                  }
                  .frame(width: 24, height: 24)
                }
              }
              .padding(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
              .cornerRadius(8)
              .overlay(
                RoundedRectangle(cornerRadius: 8)
                  .inset(by: 0.50)
                  .stroke(Color(red: 0.82, green: 0.84, blue: 0.87), lineWidth: 0.50)
              )
            }
          }
        }
        HStack(spacing: 5) {
          Text("Login now")
            .font(Font.custom("Poppins", size: 16).weight(.semibold))
            .lineSpacing(16)
            .foregroundColor(Color(red: 0.99, green: 0.99, blue: 0.99))
        }
        .padding(16)
        .frame(width: 396, height: 52)
        .background(Color(red: 0.08, green: 0.44, blue: 0.94))
        .cornerRadius(8)
      }
      .padding(EdgeInsets(top: 48, leading: 72, bottom: 48, trailing: 72))
      .frame(width: 540)
      .background(.white)
      .cornerRadius(20)
      .offset(x: 417.50, y: 13)
      .shadow(
        color: Color(red: 0.89, green: 0.90, blue: 0.92, opacity: 0.74), radius: 47.90, x: 40, y: 40
      )
      ZStack() {

      }
      .frame(width: 51, height: 51)
      .offset(x: 781, y: -471.50)
      ZStack() {
        Group {
          Rectangle()
            .foregroundColor(.clear)
            .frame(width: 46, height: 127)
            .background(Color(red: 1, green: 1, blue: 1).opacity(0.10))
            .cornerRadius(10)
            .overlay(
              RoundedRectangle(cornerRadius: 10)
                .inset(by: 0.50)
                .stroke(Color(red: 0.69, green: 0.78, blue: 0.93), lineWidth: 0.50)
            )
            .offset(x: 0, y: 0)
          Text("7")
            .font(Font.custom("Poppins", size: 14))
            .lineSpacing(14)
            .foregroundColor(.black)
            .offset(x: -0.50, y: 42.50)
          Text("5")
            .font(Font.custom("Poppins", size: 14))
            .lineSpacing(14)
            .foregroundColor(.black)
            .offset(x: -0.50, y: 10.50)
          Text("4")
            .font(Font.custom("Poppins", size: 14))
            .lineSpacing(14)
            .foregroundColor(.black)
            .offset(x: -0.50, y: -5.50)
          Text("3")
            .font(Font.custom("Poppins", size: 14))
            .lineSpacing(14)
            .foregroundColor(.black)
            .offset(x: -0.50, y: -21.50)
          Text("2")
            .font(Font.custom("Poppins", size: 14))
            .lineSpacing(14)
            .foregroundColor(.black)
            .offset(x: -0.50, y: -37.50)
          Text("6")
            .font(Font.custom("Poppins", size: 14))
            .lineSpacing(14)
            .foregroundColor(.black)
            .offset(x: -0.50, y: 26.50)
          Text("1")
            .font(Font.custom("Poppins", size: 14))
            .lineSpacing(14)
            .foregroundColor(.black)
            .offset(x: -0.50, y: -53.50)
          ZStack() {
            Rectangle()
              .foregroundColor(.clear)
              .frame(width: 46, height: 13)
              .background(Color(red: 1, green: 1, blue: 1).opacity(0.02))
              .cornerRadius(10)
              .overlay(
                RoundedRectangle(cornerRadius: 10)
                  .inset(by: 0.50)
                  .stroke(Color(red: 0.69, green: 0.78, blue: 0.93), lineWidth: 0.50)
              )
              .offset(x: 0, y: 0.50)
          }
          .frame(width: 24, height: 24)
          .offset(x: 0, y: 56.50)
          ZStack() {

          }
          .frame(width: 11, height: 11)
          .offset(x: -12.50, y: -20)
        }
      }
      .frame(width: 46, height: 127)
      .background(.white)
      .offset(x: 432.50, y: 15.50)
    }
    .frame(width: 1679, height: 1050)
    .background(Color(red: 0.98, green: 0.97, blue: 0.95));
  }
}