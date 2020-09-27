import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:wowtalent/auth/UserAuth.dart';
import 'package:wowtalent/screen/mainScreens/mainScreensWrapper.dart';

class AuthButtons{
  static final UserAuth _userAuth = UserAuth();

  static Widget socialLogin({Size size, void Function() newAccountCallback, BuildContext context}){
    double fontOne = (size.height * 0.015) / 11;
    double widthOne = size.width * 0.0008;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          onTap: () async {
            await _userAuth.signInWithFacebook().then((result){
              if(result == false){
                Scaffold.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Something went wrong try again')
                    )
                );
              }else if(result == true){
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MainScreenWrapper(
                          index: 0,
                        )
                    )
                );
              }else{
                newAccountCallback();
              }
            });
          },
          child: Image.asset(
            "assets/images/fb.png",
            scale: fontOne * 9,
          ),
        ),
        SizedBox(width: widthOne * 50,),
        InkWell(
          onTap: () async{
            await _userAuth.signInWithGoogle().then((result){
              if(result == false){
                Scaffold.of(context).showSnackBar(
                    SnackBar(
                        content: Text('Something went wrong try again')
                    )
                );
              }else if(result == true){
                Navigator.pushReplacement(
                    context,
                    MaterialPageRoute(
                        builder: (_) => MainScreenWrapper(
                          index: 0,
                        )
                    )
                );
              }else{
                newAccountCallback();
              }
            });
          },
          child: Image.asset(
            "assets/images/google.png",
            scale: fontOne * 9,
          ),
        ),
      ],
    );
  }
}
